#!/usr/bin/env python3
"""Local, file-backed organizer. No network, scheduler, or external-write authority."""

import argparse
import contextlib
import datetime as dt
import fcntl
import json
import os
from pathlib import Path
import re
import sys
import tempfile
import uuid

ROOT = Path(os.environ.get("ORGANIZER_DIR") or
            ("/organizer" if Path("/organizer").is_dir() else "/var/lib/hermes-organizer/data"))
VERSION = 1
ID = re.compile(r"^[a-z0-9][a-z0-9-]{0,63}$")


def now():
    return dt.datetime.now(dt.timezone.utc).isoformat()


def timestamp(value):
    if value is None:
        return
    parsed = dt.datetime.fromisoformat(value.replace("Z", "+00:00"))
    if parsed.tzinfo is None or parsed.utcoffset() is None:
        raise ValueError("timestamp must include a timezone offset")


def empty():
    return {"schema": VERSION, "migrations": [], "preferences": None,
            "projects": {}, "commitments": {}, "reminders": {},
            "meetings": {}, "decisions": {}, "topics": {},
            "notifications": {}, "idempotency": {}}


@contextlib.contextmanager
def locked(write=False):
    ROOT.mkdir(mode=0o700, parents=True, exist_ok=True)
    os.chmod(ROOT, 0o700)
    fd = os.open(ROOT / ".lock", os.O_CREAT | os.O_RDWR, 0o600)
    try:
        fcntl.flock(fd, fcntl.LOCK_EX if write else fcntl.LOCK_SH)
        path = ROOT / "store.json"
        data = json.loads(path.read_text()) if path.exists() else empty()
        if data.get("schema") != VERSION:
            raise ValueError("unsupported organizer schema")
        yield data
        if write:
            raw = json.dumps(data, ensure_ascii=False, indent=2, sort_keys=True) + "\n"
            tmp_fd, tmp_path = tempfile.mkstemp(prefix=".store-", dir=ROOT)
            try:
                os.fchmod(tmp_fd, 0o600)
                with os.fdopen(tmp_fd, "w") as out:
                    out.write(raw)
                    out.flush()
                    os.fsync(out.fileno())
                os.replace(tmp_path, path)
                dir_fd = os.open(ROOT, os.O_RDONLY | os.O_DIRECTORY)
                try:
                    os.fsync(dir_fd)
                finally:
                    os.close(dir_fd)
            finally:
                if os.path.exists(tmp_path):
                    os.unlink(tmp_path)
    finally:
        fcntl.flock(fd, fcntl.LOCK_UN)
        os.close(fd)


def payload(path):
    value = json.loads(Path(path).read_text())
    if not isinstance(value, dict):
        raise ValueError("payload must be a JSON object")
    return value


def record_id(value):
    if not isinstance(value, str) or not ID.fullmatch(value):
        raise ValueError("ID must be lowercase letters, digits, or hyphens")
    return value


def validate_commitment(item):
    allowed = {"id", "title", "project_id", "action_type", "acceptance", "status",
               "owner", "deadline_at", "planned_start_at", "planned_end_at",
               "reminder_at", "completed_at", "completion_evidence", "effort_estimate",
               "effort_source", "source", "external_issue", "revision", "created_at", "updated_at"}
    if set(item) - allowed:
        raise ValueError("unknown commitment fields")
    record_id(item["id"])
    if not isinstance(item.get("title"), str) or not item["title"].strip():
        raise ValueError("title required")
    if item.get("acceptance") not in ("suggested", "accepted"):
        raise ValueError("acceptance must be suggested or accepted")
    if item.get("status") not in ("open", "waiting", "done", "cancelled"):
        raise ValueError("invalid status")
    if not isinstance(item.get("source"), str) or not item["source"].strip():
        raise ValueError("source required")
    for field in ("deadline_at", "planned_start_at", "planned_end_at", "reminder_at", "completed_at"):
        timestamp(item.get(field))
    if item["status"] == "done" and not item.get("completion_evidence"):
        raise ValueError("completion evidence required")
    if item.get("project_id") is not None:
        record_id(item["project_id"])


def show(value):
    print(json.dumps(value, ensure_ascii=False, indent=2, sort_keys=True))


def import_seeds(files):
    # YAML is parsed only on the operator's one-time import path. No private
    # source path or payload is embedded in the Nix derivation.
    import yaml
    paths = [Path(p).resolve() for p in files]
    if any(str(p).startswith("/nix/store/") for p in paths):
        raise ValueError("seed files must stay outside the Nix store")
    if any(any((parent / ".git").exists() for parent in p.parents) for p in paths):
        raise ValueError("seed files must stay outside Git worktrees")
    by_name = {p.name: yaml.safe_load(p.read_text()) for p in paths}
    if set(by_name) != {"preferences.yaml", "portfolio.yaml", "topic-registry.yaml"}:
        raise ValueError("supply the three private seed files")
    if by_name["preferences.yaml"].get("schema") != "amjad-organizer-preferences-draft-v1":
        raise ValueError("unexpected preferences seed")
    if by_name["portfolio.yaml"].get("schema") != "amjad-organizer-portfolio-draft-v1":
        raise ValueError("unexpected portfolio seed")
    if by_name["topic-registry.yaml"].get("schema") != "amjad-organizer-topic-registry-draft-v1":
        raise ValueError("unexpected topic seed")
    with locked(write=True) as db:
        if "private-seed-v1" in db["migrations"]:
            show({"result": "already_imported"})
            return
        if db["preferences"] is not None or any(db[k] for k in ("projects", "commitments", "reminders", "topics")):
            raise ValueError("store is not empty; reconcile manually before import")
        db["preferences"] = {"revision": 1, "data": by_name["preferences.yaml"]}
        for project in by_name["portfolio.yaml"]["projects"]:
            ident = record_id(project["id"])
            db["projects"][ident] = {"revision": 1, "created_at": now(), "updated_at": now(), "data": project}
        # Intent is retained as preferences only. No trusted numeric identity
        # exists, so the proposed topic labels are not active bindings.
        db["preferences"]["topic_intent"] = by_name["topic-registry.yaml"]
        db["migrations"].append("private-seed-v1")
    show({"result": "imported", "projects": len(by_name["portfolio.yaml"]["projects"]), "jobs_enabled": False})


def create_commitment(item, key):
    if not key or len(key) > 200:
        raise ValueError("non-empty idempotency key required")
    item = dict(item)
    item.setdefault("id", "c-" + uuid.uuid4().hex)
    item.setdefault("status", "open")
    item.setdefault("acceptance", "suggested")
    validate_commitment(item)
    with locked(write=True) as db:
        previous = db["idempotency"].get(key)
        if previous:
            show(db["commitments"][previous])
            return
        if item["id"] in db["commitments"]:
            raise ValueError("ID already exists")
        if item.get("project_id") and item["project_id"] not in db["projects"]:
            raise ValueError("unknown project")
        item.update(revision=1, created_at=now(), updated_at=now())
        db["commitments"][item["id"]] = item
        db["idempotency"][key] = item["id"]
    show(item)


def update_commitment(ident, expected, patch):
    immutable = {"id", "revision", "created_at", "updated_at", "source"}
    if set(patch) & immutable:
        raise ValueError("cannot patch immutable fields")
    with locked(write=True) as db:
        current = db["commitments"].get(ident)
        if current is None:
            raise ValueError("unknown commitment")
        if current["revision"] != expected:
            raise ValueError("revision conflict")
        updated = {**current, **patch, "revision": expected + 1, "updated_at": now()}
        validate_commitment(updated)
        if updated.get("project_id") and updated["project_id"] not in db["projects"]:
            raise ValueError("unknown project")
        db["commitments"][ident] = updated
    show(updated)


def put_record(collection, item, expected, key):
    """Create/revise a private brief, meeting, decision, or inactive reminder."""
    if collection not in ("projects", "meetings", "decisions", "reminders"):
        raise ValueError("collection is not model-writable")
    ident = record_id(item.get("id"))
    if not isinstance(item.get("source"), str) or not item["source"].strip():
        raise ValueError("source required")
    if collection == "reminders":
        if item.get("enabled", False) is not False:
            raise ValueError("reminder activation is unavailable")
        timestamp(item.get("trigger_at"))
    if collection == "projects" and not item.get("name"):
        raise ValueError("project name required")
    if collection in ("meetings", "decisions") and not item.get("summary"):
        raise ValueError("summary required")
    with locked(write=True) as db:
        idempotency = f"{collection}:{key}" if key else None
        if idempotency and idempotency in db["idempotency"]:
            show(db[collection][db["idempotency"][idempotency]])
            return
        current = db[collection].get(ident)
        revision = current["revision"] if current else 0
        if revision != expected:
            raise ValueError("revision conflict")
        record = {"revision": revision + 1, "created_at": current["created_at"] if current else now(),
                  "updated_at": now(), "data": item}
        db[collection][ident] = record
        if idempotency:
            db["idempotency"][idempotency] = ident
    show(record)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    sub = parser.add_subparsers(dest="command", required=True)
    seed = sub.add_parser("import-seeds")
    seed.add_argument("files", nargs=3)
    sub.add_parser("status")
    listing = sub.add_parser("list")
    listing.add_argument("collection", choices=("projects", "commitments", "reminders", "meetings", "decisions", "topics", "notifications"))
    get = sub.add_parser("get")
    get.add_argument("collection", choices=("projects", "commitments", "reminders", "meetings", "decisions", "topics", "notifications", "preferences"))
    get.add_argument("id", nargs="?")
    create = sub.add_parser("capture")
    create.add_argument("json_file")
    create.add_argument("--idempotency-key", required=True)
    update = sub.add_parser("update")
    update.add_argument("id")
    update.add_argument("--expected-revision", type=int, required=True)
    update.add_argument("json_file")
    put = sub.add_parser("put")
    put.add_argument("collection", choices=("projects", "meetings", "decisions", "reminders"))
    put.add_argument("json_file")
    put.add_argument("--expected-revision", type=int, required=True)
    put.add_argument("--idempotency-key")
    args = parser.parse_args()
    if args.command == "import-seeds":
        import_seeds(args.files)
    elif args.command == "capture":
        create_commitment(payload(args.json_file), args.idempotency_key)
    elif args.command == "update":
        update_commitment(args.id, args.expected_revision, payload(args.json_file))
    elif args.command == "put":
        put_record(args.collection, payload(args.json_file), args.expected_revision, args.idempotency_key)
    else:
        with locked() as db:
            if args.command == "status":
                show({"schema": db["schema"], "migrations": db["migrations"],
                      "counts": {k: len(db[k]) for k in ("projects", "commitments", "reminders", "topics", "notifications")},
                      "routines_enabled": False, "external_writes_enabled": False})
            elif args.command == "list":
                show(list(db[args.collection].values()))
            elif args.command == "get":
                if args.collection != "preferences" and not args.id:
                    raise ValueError("ID required")
                show(db[args.collection] if args.collection == "preferences" else db[args.collection].get(args.id))


if __name__ == "__main__":
    try:
        main()
    except (ValueError, KeyError, FileNotFoundError, json.JSONDecodeError) as exc:
        print(f"organizer: {exc}", file=sys.stderr)
        sys.exit(2)
