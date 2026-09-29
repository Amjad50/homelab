import contextlib
import datetime as dt
import importlib.util
import io
import json
import os
from pathlib import Path
import sqlite3
import sys
import tempfile
import unittest

HERE = Path(__file__).parent


def module(name):
    spec = importlib.util.spec_from_file_location(name, HERE / (name + ".py"))
    loaded = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(loaded)
    return loaded


organizer = module("organizer")
schedule = module("schedule")
bind = module("bind")


class OrganizerTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        organizer.ROOT = Path(self.temp.name) / "data"

    def tearDown(self):
        self.temp.cleanup()

    @staticmethod
    def jakim_week(start):
        """A seven-day WLY01 payload shaped like the live e-Solat response."""
        rows = []
        for i in range(7):
            day = start + dt.timedelta(days=i)
            month = "Sep" if day.month == 9 else "Okt"
            rows.append({"date": f"{day.day:02d}-{month}-{day.year}",
                         "fajr": "05:55:00", "dhuhr": "13:08:00", "asr": "16:15:00",
                         "maghrib": "19:10:00", "isha": "20:19:00"})
        payload = {"status": "OK!", "zone": "WLY01", "periodType": "duration",
                   "prayerTime": rows}
        fetched = dt.datetime(2026, 9, 27, tzinfo=dt.timezone.utc)
        return schedule.parse_api(json.dumps(payload), start,
                                  start + dt.timedelta(days=6), fetched)

    def test_reconcile_publishes_the_week_with_every_routine_off(self):
        root = Path(self.temp.name)
        control = root / "cron-control.json"
        control.write_text(json.dumps({"desk_delivery": "telegram:1:2", "morning": False,
                                       "checkin": False, "review": False}))
        published = root / "prayer-timetable.json"
        tables = self.jakim_week(dt.date(2026, 9, 27))
        saved = (schedule.CONTROL, schedule.LOCK, schedule.TIMETABLE, schedule.fetch_range,
                 schedule.pause_disabled, schedule.reconcile, sys.argv)
        try:
            schedule.CONTROL = control
            schedule.LOCK = root / ".lock"
            schedule.TIMETABLE = published
            schedule.fetch_range = lambda start, end: tables
            schedule.pause_disabled = lambda *args, **kwargs: None
            schedule.reconcile = lambda *args, **kwargs: self.fail("nothing may be scheduled")
            sys.argv = ["schedule.py", "--reconcile"]
            with contextlib.redirect_stdout(io.StringIO()):
                schedule.main()
        finally:
            (schedule.CONTROL, schedule.LOCK, schedule.TIMETABLE, schedule.fetch_range,
             schedule.pause_disabled, schedule.reconcile, sys.argv) = saved
        self.assertEqual(oct(published.stat().st_mode & 0o777), "0o444")
        self.assertEqual(json.loads(published.read_text())["covers"],
                         {"start": "2026-09-27", "end": "2026-10-03"})

    def test_revision_idempotency_and_atomic_failure(self):
        item = {"id": "c-fixture", "title": "Review scope", "acceptance": "accepted",
                "status": "open", "source": "fixture:1"}
        organizer.create_commitment(item, "fixture:1")
        organizer.create_commitment(item, "fixture:1")
        with organizer.locked() as db:
            self.assertEqual(len(db["commitments"]), 1)
        organizer.update_commitment("c-fixture", 1, {"title": "Review revised scope"})
        with self.assertRaisesRegex(ValueError, "revision conflict"):
            organizer.update_commitment("c-fixture", 1, {"title": "Stale overwrite"})
        with self.assertRaisesRegex(ValueError, "completion evidence"):
            organizer.update_commitment("c-fixture", 2, {"status": "done"})
        with organizer.locked() as db:
            self.assertEqual(db["commitments"]["c-fixture"]["title"], "Review revised scope")

    def test_seed_once_never_overwrites(self):
        seed_root = Path(os.environ.get("HERMES_SECRETARY_SEED_DIR", "/nonexistent"))
        seeds = [str(seed_root / name)
                 for name in ("preferences.yaml", "portfolio.yaml", "topic-registry.yaml")]
        if not all(Path(p).exists() for p in seeds):
            self.skipTest("private seeds unavailable")
        organizer.import_seeds(seeds)
        with organizer.locked(write=True) as db:
            db["projects"]["sadeem"]["data"]["reported_state"] = "live edit"
        organizer.import_seeds(seeds)
        with organizer.locked() as db:
            self.assertEqual(db["projects"]["sadeem"]["data"]["reported_state"], "live edit")
            self.assertEqual(db["topics"], {})

    def test_records_cannot_activate_routines(self):
        with self.assertRaisesRegex(ValueError, "activation is unavailable"):
            organizer.put_record("reminders", {"id": "r-1", "source": "fixture", "enabled": True}, 0, "r-1")
        organizer.put_record("reminders", {"id": "r-1", "source": "fixture", "enabled": False,
                                                   "trigger_at": "2026-09-25T17:00:00+08:00"}, 0, "r-1")
        with self.assertRaisesRegex(ValueError, "revision conflict"):
            organizer.put_record("reminders", {"id": "r-1", "source": "fixture", "enabled": False}, 0, "new")
        with organizer.locked() as db:
            self.assertFalse(db["reminders"]["r-1"]["data"]["enabled"])

    def test_friday_and_stale_data(self):
        table = {"date": "2026-09-25", "zone": "WLY01", "source": "fixture",
                 "fetched_at": "2026-09-24T00:00:00Z",
                 "times": {"fajr": "05:50", "dhuhr": "13:20", "asr": "16:30",
                           "maghrib": "19:20", "isha": "20:30"}}
        result = schedule.resolve(table, dt.date(2026, 9, 25))
        self.assertEqual(result["routines"]["after_asr"]["name"], "weekly_review")
        self.assertEqual(result["routines"]["after_asr"]["earliest"], "2026-09-25T17:00:00+08:00")
        self.assertEqual(result["protected_windows"]["jumuah"]["status"], "provisional; mosque time required")
        self.assertNotIn("dhuhr", result["protected_windows"])
        with self.assertRaisesRegex(ValueError, "date/zone mismatch"):
            schedule.resolve(table, dt.date(2026, 9, 26))
        table["zone"] = "SGR01"
        with self.assertRaisesRegex(ValueError, "date/zone mismatch"):
            schedule.resolve(table, dt.date(2026, 9, 25))

    def test_jakim_week_and_friday_replacement(self):
        start = dt.date(2026, 9, 27)
        rows = []
        for i in range(7):
            day = start + dt.timedelta(days=i)
            month = "Sep" if day.month == 9 else "Okt"
            rows.append({"date": f"{day.day:02d}-{month}-{day.year}",
                         "fajr": "05:55:00", "dhuhr": "13:08:00", "asr": "16:15:00",
                         "maghrib": "19:10:00", "isha": "20:19:00"})
        payload = {"status": "OK!", "zone": "WLY01", "periodType": "duration",
                   "prayerTime": rows}
        fetched = dt.datetime(2026, 9, 27, tzinfo=dt.timezone.utc)
        tables = schedule.parse_api(__import__("json").dumps(payload), start,
                                    start + dt.timedelta(days=6), fetched)
        jobs = schedule.plan_week(tables)
        self.assertEqual(len(jobs), 14)
        self.assertEqual(jobs[0]["schedule"], "2026-09-27T06:55:00+08:00")
        friday = [j for j in jobs if j["date"] == "2026-10-02"]
        self.assertEqual([j["kind"] for j in friday], ["morning", "review"])
        tables[1]["times"]["fajr"] = "05:56"
        adjusted = schedule.plan_week(tables)
        self.assertEqual([j["schedule"] for j in adjusted if j["kind"] == "morning"][:2],
                         ["2026-09-27T06:55:00+08:00", "2026-09-28T06:55:00+08:00"])
        tables[2]["times"]["fajr"] = "05:59"
        adjusted = schedule.plan_week(tables)
        self.assertEqual([j["schedule"] for j in adjusted if j["kind"] == "morning"][2],
                         "2026-09-29T06:59:00+08:00")
        payload["zone"] = "SGR01"
        with self.assertRaisesRegex(ValueError, "zone"):
            schedule.parse_api(__import__("json").dumps(payload), start,
                               start + dt.timedelta(days=6), fetched)
        payload["zone"] = "WLY01"
        payload["prayerTime"].pop()
        with self.assertRaisesRegex(ValueError, "cover"):
            schedule.parse_api(__import__("json").dumps(payload), start,
                               start + dt.timedelta(days=6), fetched)

    def test_verified_week_is_published_read_only(self):
        start = dt.date(2026, 9, 27)
        tables = self.jakim_week(start)
        path = Path(self.temp.name) / "prayer-timetable.json"
        schedule.write_timetable(tables, path=path)
        self.assertEqual(oct(path.stat().st_mode & 0o777), "0o444")
        document = json.loads(path.read_text())
        self.assertEqual(document["zone"], "WLY01")
        self.assertEqual(document["covers"], {"start": "2026-09-27", "end": "2026-10-03"})
        self.assertEqual([day["date"] for day in document["days"]],
                         [(start + dt.timedelta(days=i)).isoformat() for i in range(7)])
        self.assertNotIn("dry_run", document["days"][0])
        self.assertIn("fajr", document["days"][0]["protected_windows"])
        self.assertEqual(document["days"][5]["weekday"], "friday")
        self.assertNotIn("dhuhr", document["days"][5]["protected_windows"])
        # A later weekly refresh replaces the read-only file instead of failing on it.
        schedule.write_timetable(tables, path=path)
        self.assertEqual(oct(path.stat().st_mode & 0o777), "0o444")

    def test_prompt_points_at_read_only_published_timetable(self):
        prompt = schedule._prompt({"name": "secretary-morning-2026-09-28",
                                   "kind": "morning", "date": "2026-09-28",
                                   "schedule": "2026-09-28T06:55:00+08:00"})
        self.assertIn("/organizer/prayer-timetable.json", prompt)
        self.assertIn("never edit", prompt)

    def test_native_cron_upsert_and_disabled_routines(self):
        job = {"name": "secretary-morning-2026-09-28", "kind": "morning",
               "schedule": "2026-09-28T06:55:00+08:00", "date": "2026-09-28"}
        control = {"desk_delivery": "telegram:123:456", "morning": True,
                   "checkin": False, "review": False}
        calls = []
        existing = {}

        class FakeJobs:
            def resolve_job_ref(self, name):
                return existing.get(name)

            def update_job(self, job_id, changes):
                calls.append(("update", job_id, changes))

            def pause_job(self, job_id, reason):
                calls.append(("pause", job_id, reason))
                existing[job_id]["enabled"] = False

        def create(**kwargs):
            calls.append(("create", kwargs))
            existing[kwargs["name"]] = {"id": kwargs["name"], "enabled": True}

        backend = (FakeJobs(), create)

        instant = dt.datetime(2026, 9, 27, tzinfo=schedule.ZONE)
        self.assertEqual(schedule.reconcile([job], control, backend=backend, now=instant),
                         [(job["name"], "created")])
        self.assertTrue(calls[0][1]["attach_to_session"])
        self.assertEqual(schedule.reconcile([job], control, backend=backend, now=instant),
                         [(job["name"], "updated")])
        self.assertEqual(sum(c[0] == "create" for c in calls), 1)
        control["morning"] = False
        self.assertEqual(schedule.reconcile([job], control, backend=backend, now=instant), [])
        self.assertEqual(sum(c[0] == "create" for c in calls), 1)
        schedule.pause_disabled(control, dt.date(2026, 9, 28), api=backend[0])
        self.assertIn(("pause", job["name"], "Secretary routine disabled by owner control"), calls)
        control["morning"] = True
        self.assertEqual(schedule.reconcile([job], control, backend=backend,
                                            now=dt.datetime(2026, 9, 28, 7, tzinfo=schedule.ZONE)), [])


class BindTests(unittest.TestCase):
    """Desk identity must come from gateway records, never from text or config."""

    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.database = Path(self.temp.name) / "state.db"
        connection = sqlite3.connect(self.database)
        connection.executescript(
            "create table sessions (id text, source text, chat_id text, thread_id text,"
            " user_id text);"
            "create table messages (id text, session_id text, role text, content text,"
            " timestamp real);")
        connection.commit()
        connection.close()

    def tearDown(self):
        self.temp.cleanup()

    def record(self, ident, session, thread, user, role, content, stamp,
               chat="28737678"):
        connection = sqlite3.connect(self.database)
        connection.execute("insert into sessions values (?,?,?,?,?)",
                           (session, "telegram", chat, thread, user))
        connection.execute("insert into messages values (?,?,?,?,?)",
                           (ident, session, role, content, stamp))
        connection.commit()
        connection.close()

    def test_command_forms_normalise(self):
        for text in ("/desk-setup", "desk setup", "  /Desk-Setup  ", "desk_setup",
                     "/desk-setup@my_bot"):
            self.assertEqual(bind.normalize(text), "desk-setup")
        self.assertEqual(bind.normalize("good morning"), "good-morning")
        self.assertEqual(bind.normalize(None), "")

    def test_either_word_order_is_a_marker(self):
        for text in ("desk setup", "setup desk", "desk-setup", "setup-desk"):
            self.assertIn(bind.normalize(text), {bind.normalize(m) for m in bind.MARKERS})

    def test_skill_invocation_scaffold_binds(self):
        # The gateway dispatches slash commands itself, so the raw text is never
        # stored; the recorded scaffold carries the same trusted session.
        scaffold = ('[IMPORTANT: The user has invoked the "desk-setup" skill, '
                    'indicating that it is relevant to the current task. The full '
                    'skill content is loaded below.]\n\n# Desk setup\n...')
        self.record("m1", "s1", "137749", "28737678", "user", scaffold, 100.0)
        request = bind.find_request(self.database, {"28737678"})
        self.assertIsNotNone(request)
        self.assertEqual(request["thread_id"], "137749")

    def test_an_unrelated_skill_scaffold_does_not_bind(self):
        scaffold = ('[IMPORTANT: The user has invoked the "secretary" skill, '
                    'indicating that it is relevant to the current task.]')
        self.record("m1", "s1", "137749", "28737678", "user", scaffold, 100.0)
        self.assertIsNone(bind.find_request(self.database, {"28737678"}))

    def test_owner_ids_accept_separators(self):
        self.assertEqual(bind.owner_ids({"TELEGRAM_ALLOWED_USERS": "1, 2 ;3"}),
                         {"1", "2", "3"})
        self.assertEqual(bind.owner_ids({}), set())

    def test_bind_uses_gateway_identity(self):
        self.record("m1", "s1", "137749", "28737678", "user", "/setup-desk", 100.0)
        request = bind.find_request(self.database, {"28737678"})
        self.assertEqual(request["chat_id"], "28737678")
        self.assertEqual(request["thread_id"], "137749")
        self.assertEqual(bind.control_for(request),
                         {"desk_delivery": "telegram:28737678:137749",
                          "morning": True, "checkin": True, "review": True})

    def test_foreign_owner_and_other_text_are_ignored(self):
        self.record("m1", "s1", "1", "999", "user", "/setup-desk", 100.0)
        self.record("m2", "s2", "2", "28737678", "user", "hello", 101.0)
        self.record("m3", "s3", "3", "28737678", "assistant", "/setup-desk", 102.0)
        self.assertIsNone(bind.find_request(self.database, {"28737678"}))

    def test_only_the_newest_unclaimed_request_binds(self):
        self.record("m1", "s1", "111", "28737678", "user", "/setup-desk", 100.0)
        self.record("m2", "s2", "222", "28737678", "user", "setup desk", 200.0)
        self.assertEqual(bind.find_request(self.database, {"28737678"})["thread_id"], "222")
        # A consumed request must never re-point delivery at an older topic.
        self.assertIsNone(bind.find_request(self.database, {"28737678"}, after=200.0))

    def test_a_topic_less_session_cannot_bind(self):
        self.record("m1", "s1", None, "28737678", "user", "/setup-desk", 100.0)
        self.assertIsNone(bind.find_request(self.database, {"28737678"}))

    def test_written_control_satisfies_the_reconciler(self):
        path = Path(self.temp.name) / "cron-control.json"
        control = {"desk_delivery": "telegram:28737678:137749", "morning": True,
                   "checkin": True, "review": True}
        self.assertTrue(bind.write_control(control, path))
        self.assertFalse(bind.write_control(control, path))
        self.assertEqual(oct(path.stat().st_mode & 0o777), "0o600")
        self.assertEqual(schedule.read_control(path), control)

    def test_control_path_matches_the_scheduler_default(self):
        self.assertEqual(str(bind.CONTROL), str(schedule.CONTROL))

    def test_consumed_marker_is_recorded(self):
        path = Path(self.temp.name) / ".desk-bind-consumed"
        self.assertEqual(bind.consumed_at(path), 0.0)
        bind.write_text(path, "200.000000\n")
        self.assertEqual(bind.consumed_at(path), 200.0)

    def test_dotenv_values_are_json_decoded(self):
        env = bind.parse_env('# comment\nTELEGRAM_ALLOWED_USERS="1,2"\nPLAIN=raw\n')
        self.assertEqual(env["TELEGRAM_ALLOWED_USERS"], "1,2")
        self.assertEqual(env["PLAIN"], "raw")


if __name__ == "__main__":
    unittest.main()
