#!/usr/bin/env python3
"""Verified WLY01 lookup and optional native Hermes cron reconciliation."""

import argparse
import datetime as dt
import fcntl
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import sys
import tempfile
from zoneinfo import ZoneInfo

ZONE = ZoneInfo("Asia/Kuala_Lumpur")
PRAYERS = ("fajr", "dhuhr", "asr", "maghrib", "isha")
API = "https://www.e-solat.gov.my/index.php?r=esolatApi/takwimsolat&period=duration&zone=WLY01"
SOURCE = "JAKIM e-Solat WLY01 duration API"
CONTROL = Path("/var/lib/hermes-organizer/cron-control.json")
LOCK = Path("/var/lib/hermes-organizer/.prayer-refresh.lock")
# Shared with the Docker terminal at /organizer, so the agent can read the week
# the host verified instead of guessing prayer times.
TIMETABLE = Path("/var/lib/hermes-organizer/data/prayer-timetable.json")
WORKDIR = Path("/var/lib/hermes/workspace")
MONTHS = {"jan": 1, "feb": 2, "mac": 3, "mar": 3, "apr": 4, "mei": 5,
          "may": 5, "jun": 6, "jul": 7, "ogo": 8, "aug": 8, "sep": 9,
          "okt": 10, "oct": 10, "nov": 11, "dis": 12, "dec": 12}


def resolve(timetable, date):
    if timetable.get("date") != date.isoformat() or timetable.get("zone") != "WLY01":
        raise ValueError("timetable date/zone mismatch")
    if not timetable.get("source") or not timetable.get("fetched_at"):
        raise ValueError("source and fetched_at required")
    fetched = dt.datetime.fromisoformat(timetable["fetched_at"].replace("Z", "+00:00"))
    if fetched.tzinfo is None:
        raise ValueError("fetched_at must be timezone-aware")
    instants = {}
    for name in PRAYERS:
        value = timetable.get("times", {}).get(name)
        if not isinstance(value, str) or not re.fullmatch(r"[0-2][0-9]:[0-5][0-9]", value):
            raise ValueError(f"missing or invalid {name}")
        hour, minute = map(int, value.split(":"))
        instants[name] = dt.datetime.combine(date, dt.time(hour, minute), tzinfo=ZONE)
    if list(instants.values()) != sorted(instants.values()) or len(set(instants.values())) != 5:
        raise ValueError("unordered prayer timetable")
    delta = dt.timedelta(minutes=30)
    windows = {name: {"start": (t - dt.timedelta(minutes=5)).isoformat(),
                      "end": (t + delta).isoformat()} for name, t in instants.items()}
    if date.weekday() == 4:
        windows.pop("dhuhr")
        windows["jumuah"] = {"status": "provisional; mosque time required"}
    return {"date": date.isoformat(), "zone": "WLY01", "source": timetable["source"],
            "fetched_at": fetched.isoformat(), "protected_windows": windows,
            "routines": {
                "morning_brief_candidate": (instants["fajr"] + dt.timedelta(minutes=60)).isoformat(),
                "after_asr": {"name": "weekly_review" if date.weekday() == 4 else "checkin",
                               "earliest": (instants["asr"] + delta).isoformat()}}, "dry_run": True}


def _api_date(value):
    match = re.fullmatch(r"(\d{1,2})-([A-Za-z]+)-(\d{4})", value or "")
    if not match or match[2].lower() not in MONTHS:
        raise ValueError(f"invalid JAKIM date: {value!r}")
    return dt.date(int(match[3]), MONTHS[match[2].lower()], int(match[1]))


def parse_api(body, start, end, fetched_at):
    payload = json.loads(body)
    if (payload.get("status") != "OK!" or payload.get("zone") != "WLY01"
            or payload.get("periodType") != "duration"):
        raise ValueError("unexpected JAKIM response status, zone, or period")
    rows = payload.get("prayerTime")
    if not isinstance(rows, list) or len(rows) != (end - start).days + 1:
        raise ValueError("JAKIM response does not cover requested range")
    tables = []
    for offset, row in enumerate(rows):
        day = start + dt.timedelta(days=offset)
        if not isinstance(row, dict) or _api_date(row.get("date")) != day:
            raise ValueError("JAKIM response has missing or unordered dates")
        times = {}
        for prayer in PRAYERS:
            raw = row.get(prayer)
            if not isinstance(raw, str) or not re.fullmatch(r"\d\d:\d\d:00", raw):
                raise ValueError(f"invalid JAKIM {prayer} time for {day}")
            times[prayer] = raw[:5]
        table = {"date": day.isoformat(), "zone": "WLY01", "source": SOURCE,
                 "fetched_at": fetched_at.isoformat(), "times": times}
        resolve(table, day)
        tables.append(table)
    return tables


def fetch_range(start, end, *, runner=subprocess.run, now=None):
    if end < start or (end - start).days > 7:
        raise ValueError("request one to eight dates")
    curl = shutil.which("curl") or "/run/current-system/sw/bin/curl"
    command = [curl, "--fail", "--silent", "--show-error",
               "--connect-timeout", "5", "--max-time", "15", "--max-filesize", "131072",
               "--proto", "=https", "--data-urlencode", f"datestart={start.isoformat()}",
               "--data-urlencode", f"dateend={end.isoformat()}", API]
    result = runner(command, capture_output=True, text=True, check=True, timeout=20)
    return parse_api(result.stdout, start, end, now or dt.datetime.now(dt.timezone.utc))


def plan_week(tables):
    jobs = []
    for table in tables:
        day = dt.date.fromisoformat(table["date"])
        routine = resolve(table, day)["routines"]
        jobs.append({"name": f"secretary-morning-{day}", "kind": "morning",
                     "schedule": routine["morning_brief_candidate"], "date": day.isoformat()})
        after = routine["after_asr"]
        kind = "review" if after["name"] == "weekly_review" else "checkin"
        jobs.append({"name": f"secretary-{kind}-{day}", "kind": kind,
                     "schedule": after["earliest"], "date": day.isoformat()})
    # A single approximate time is easier to understand when the coming week
    # varies by at most two minutes. Pick the earliest, so it is never late;
    # use each dated time when that bound does not hold.
    for kind in ("morning", "checkin", "review"):
        group = [job for job in jobs if job["kind"] == kind]
        if not group:
            continue
        minute_of_day = [dt.datetime.fromisoformat(job["schedule"]).hour * 60
                         + dt.datetime.fromisoformat(job["schedule"]).minute for job in group]
        if max(minute_of_day) - min(minute_of_day) <= 2:
            earliest = min(minute_of_day)
            for job in group:
                day = dt.date.fromisoformat(job["date"])
                job["schedule"] = dt.datetime.combine(
                    day, dt.time(earliest // 60, earliest % 60), tzinfo=ZONE).isoformat()
    return jobs


def write_timetable(tables, *, path=TIMETABLE):
    """Publish the verified week for the agent to read.

    The host owns this file: it is replaced whole, marked read-only, and never
    read back, so a terminal-side edit cannot influence a later refresh.
    """
    days = []
    for table in tables:
        day = resolve(table, dt.date.fromisoformat(table["date"]))
        day.pop("dry_run")
        day["times"] = dict(table["times"])
        day["weekday"] = dt.date.fromisoformat(table["date"]).strftime("%A").lower()
        days.append(day)
    document = {
        "schema": 1,
        "provider": "JAKIM e-Solat",
        "zone": "WLY01",
        "refresh": "hermes-prayer-refresh on the gateway host, weekly and at gateway start",
        "read_only": "Reference data. Read it; never edit, move, or delete it.",
        "refreshed_at": dt.datetime.now(ZONE).isoformat(),
        "covers": {"start": days[0]["date"], "end": days[-1]["date"]},
        "days": days,
    }
    raw = json.dumps(document, indent=2, sort_keys=True) + "\n"
    path.parent.mkdir(mode=0o700, parents=True, exist_ok=True)
    tmp_fd, tmp_path = tempfile.mkstemp(prefix=".prayer-", dir=path.parent)
    try:
        os.fchmod(tmp_fd, 0o444)
        with os.fdopen(tmp_fd, "w") as out:
            out.write(raw)
            out.flush()
            os.fsync(out.fileno())
        os.replace(tmp_path, path)
    finally:
        if os.path.exists(tmp_path):
            os.unlink(tmp_path)
    return path


def read_control(path=CONTROL):
    if not path.exists():
        return None
    control = json.loads(path.read_text())
    target = control.get("desk_delivery")
    if not isinstance(target, str) or not re.fullmatch(r"telegram:-?\d+:\d+", target):
        raise ValueError("control needs verified telegram:chat_id:thread_id Desk delivery")
    for key in ("morning", "checkin", "review"):
        if type(control.get(key)) is not bool:
            raise ValueError(f"control needs boolean {key}")
    return control


TIMETABLE_NOTE = (
    "Today's verified prayer timetable is published read-only at "
    "/organizer/prayer-timetable.json by the host's weekly WLY01 refresh; read it for "
    "protected windows. It is reference data: never edit, move, delete, re-fetch, or "
    "recompute it, and if the routine date is outside its coverage or the file is "
    "missing, say so instead of guessing.")


def _prompt(job):
    tasks = {"morning": "Read current organizer records, then send a concise morning briefing with verified commitments and clearly proposed plans.",
             "checkin": "Read today's current commitments and context, then send one brief, relevant optional check-in after Asr. Do not use a canned message or invent progress.",
             "review": "Read current organizer records, then send the optional weekly review after Asr instead of the ordinary check-in. Do not invent progress."}
    return (f"Secretary {job['kind']} for {job['date']} (Asia/Kuala_Lumpur). "
            + tasks[job["kind"]] + " " + TIMETABLE_NOTE
            + " Use the secretary skill. Do not chase an unanswered message.")


def _cron_api():
    # Imported only in gateway-side reconciliation. The dry run and tests need
    # no Hermes installation. The pinned library owns its locking and store.
    from cron import jobs
    from cron.scheduler import create_job_with_scheduler_registration
    return jobs, create_job_with_scheduler_registration


def reconcile(jobs, control, *, backend=None, now=None):
    """Upsert only enabled future secretary slots through pinned Hermes APIs."""
    api, create = backend or _cron_api()
    instant = now or dt.datetime.now(ZONE)
    changes = []
    for job in jobs:
        if not control[job["kind"]] or dt.datetime.fromisoformat(job["schedule"]) <= instant:
            continue
        prompt = _prompt(job)
        common = {"deliver": control["desk_delivery"], "failure_deliver": "local",
                  "workdir": str(WORKDIR), "skills": ["secretary"],
                  "attach_to_session": True}
        existing = api.resolve_job_ref(job["name"])
        if existing:
            api.update_job(existing["id"], {"schedule": job["schedule"], "prompt": prompt, **common})
            changes.append((job["name"], "updated"))
            continue
        create(schedule=job["schedule"], prompt=prompt, name=job["name"], **common)
        changes.append((job["name"], "created"))
    return changes


def pause_disabled(control, start, *, api=None):
    """Turning a routine off stops any remaining slots without touching other jobs."""
    api = api or _cron_api()[0]
    for offset in range(7):
        day = start + dt.timedelta(days=offset)
        kinds = ("morning", "review" if day.weekday() == 4 else "checkin")
        for kind in kinds:
            if control[kind]:
                continue
            name = f"secretary-{kind}-{day}"
            existing = api.resolve_job_ref(name)
            if existing and existing.get("enabled", True):
                api.pause_job(existing["id"], reason="Secretary routine disabled by owner control")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("timetable_json", nargs="?", help="legacy verified daily JSON")
    parser.add_argument("--date", help="legacy daily date, YYYY-MM-DD")
    parser.add_argument("--week-start", help="first of seven dates; default today in Kuala Lumpur")
    parser.add_argument("--reconcile", action="store_true", help="sync enabled routines to native cron")
    args = parser.parse_args()
    if args.timetable_json:
        if not args.date or args.reconcile:
            parser.error("daily JSON requires --date and cannot reconcile")
        print(json.dumps(resolve(json.loads(Path(args.timetable_json).read_text()),
                                 dt.date.fromisoformat(args.date)), indent=2))
        return
    start = dt.date.fromisoformat(args.week_start) if args.week_start else dt.datetime.now(ZONE).date()
    if args.reconcile:
        if args.week_start:
            parser.error("--week-start is for dry runs only")
        LOCK.parent.mkdir(parents=True, exist_ok=True)
        with LOCK.open("a+") as lock:
            fcntl.flock(lock, fcntl.LOCK_EX)
            control = read_control(CONTROL)
            if control is None:
                return
            pause_disabled(control, start)
            # The timetable is published even with every routine off, so a
            # question in chat never depends on a routine being active.
            tables = fetch_range(start, start + dt.timedelta(days=6))
            written = write_timetable(tables, path=TIMETABLE)
            jobs = (reconcile(plan_week(tables), control)
                    if any(control[k] for k in ("morning", "checkin", "review")) else [])
            print(json.dumps({"timetable": str(written), "jobs": jobs}))
    else:
        tables = fetch_range(start, start + dt.timedelta(days=6))
        print(json.dumps({"source": SOURCE, "zone": "WLY01", "dry_run": True,
                          "jobs": plan_week(tables)}, indent=2))


if __name__ == "__main__":
    try:
        main()
    except (ValueError, subprocess.SubprocessError, OSError, RuntimeError) as exc:
        print(f"prayer refresh failed: {exc}", file=sys.stderr)
        sys.exit(1)
