#!/usr/bin/env python3
"""Bind the secretary Desk destination from an explicit owner command.

Delivery identity never comes from model text or a topic title. It is read from
the gateway's own session records, which carry the authenticated chat, thread,
and user identity for every conversation. The binder acts only when the owner
has asked to bind, and records the request it consumed so an old marker can
never re-point delivery at a different topic later.

Binding enables the standing routines. Turning one off afterwards is a normal
Hermes cron pause, which the weekly reconcile never resumes.
"""

import argparse
import json
import os
from pathlib import Path
import re
import sqlite3
import subprocess
import sys

# Must stay identical to schedule.CONTROL; asserted by the unit tests.
CONTROL = Path("/var/lib/hermes-organizer/cron-control.json")
CONSUMED = Path("/var/lib/hermes-organizer/.desk-bind-consumed")
DEFAULT_DATABASE = "/var/lib/hermes/.hermes/state.db"
ROUTINES = ("morning", "checkin", "review")
MARKERS = ("setup-desk", "setup desk", "desk-setup", "desk setup",
           "bind-desk", "bind desk")
# A slash command is dispatched by the gateway, so its raw text is never stored.
# The pinned revision records a skill invocation as a scaffolded user turn, and
# that scaffold carries the same trusted session. Matched loosely so an added
# instruction after the command still binds.
SCAFFOLD = 'invoked the "desk-setup" skill'
TRUE = ("true", "1", "yes", "on")
FALSE = ("false", "0", "no", "off", "")


def parse_env(text):
    """Read the deployment dotenv, whose values the generator JSON-encodes."""
    values = {}
    for line in text.splitlines():
        line = line.strip()
        if not line or line.startswith("#") or "=" not in line:
            continue
        key, _, raw = line.partition("=")
        key = key.strip()
        if not key:
            continue
        try:
            decoded = json.loads(raw)
        except json.JSONDecodeError:
            decoded = raw
        values[key] = decoded if isinstance(decoded, str) else json.dumps(decoded)
    return values


def owner_ids(env):
    raw = str(env.get("TELEGRAM_ALLOWED_USERS", ""))
    return {part.strip() for part in raw.replace(";", ",").split(",") if part.strip()}


def normalize(text):
    """Reduce a command to a comparable form: /Setup-Desk@bot -> setup-desk."""
    text = (text or "").strip().split("@", 1)[0].lstrip("/").lower()
    return re.sub(r"[\s_-]+", "-", text).strip("-")


def find_request(database, owners, after=0.0, markers=MARKERS):
    """Newest owner bind request recorded by the gateway, or None."""
    wanted = {normalize(marker) for marker in markers}
    query = """
        select m.id, m.timestamp, s.chat_id, s.thread_id, s.user_id, m.content
        from messages m join sessions s on s.id = m.session_id
        where s.source = 'telegram' and m.role = 'user' and m.timestamp > ?
        order by m.timestamp desc
    """
    connection = sqlite3.connect(f"file:{database}?mode=ro", uri=True)
    try:
        for ident, stamp, chat, thread, user, content in connection.execute(query, (after,)):
            if str(user) not in owners:
                continue
            body = content or ""
            if normalize(body) not in wanted and SCAFFOLD not in body:
                continue
            if not chat or not thread:
                continue
            return {"message_id": str(ident), "timestamp": float(stamp),
                    "chat_id": str(chat), "thread_id": str(thread)}
    finally:
        connection.close()
    return None


def consumed_at(path=CONSUMED):
    try:
        return float(path.read_text().strip())
    except (OSError, ValueError):
        return 0.0


def write_text(path, payload, mode=0o600):
    """Atomically replace a private runtime file."""
    path = Path(path)
    path.parent.mkdir(mode=0o700, parents=True, exist_ok=True)
    os.chmod(path.parent, 0o700)
    tmp = path.with_name(path.name + ".new")
    descriptor = os.open(tmp, os.O_WRONLY | os.O_CREAT | os.O_TRUNC, mode)
    with os.fdopen(descriptor, "w") as handle:
        handle.write(payload)
        handle.flush()
        os.fsync(handle.fileno())
    os.replace(tmp, path)


def control_for(request):
    """A bind enables every routine; the owner turns off what they do not want."""
    return {"desk_delivery": f"telegram:{request['chat_id']}:{request['thread_id']}",
            **{name: True for name in ROUTINES}}


def write_control(control, path=CONTROL):
    payload = json.dumps(control, ensure_ascii=False, indent=2, sort_keys=True) + "\n"
    path = Path(path)
    if path.exists() and path.read_text() == payload:
        return False
    write_text(path, payload)
    return True


def refresh(home=None, runner=subprocess.run):
    """Reconcile immediately so a fresh bind schedules this week's slots."""
    root = home or os.environ.get("HERMES_HOME")
    script = Path(root) / "scripts" / "prayer-refresh.py" if root else None
    if script is None or not script.is_file():
        return False
    runner([sys.executable, str(script)], check=False, timeout=180)
    return True


def main():
    os.umask(0o077)
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--database",
                        default=os.environ.get("HERMES_STATE_DB", DEFAULT_DATABASE))
    parser.add_argument("--home", default=os.environ.get("HERMES_HOME"))
    parser.add_argument("--dry-run", action="store_true",
                        help="report the request that would be bound, change nothing")
    arguments = parser.parse_args()

    if not arguments.home:
        raise ValueError("HERMES_HOME must be set")
    env = parse_env((Path(arguments.home) / ".env").read_text())
    owners = owner_ids(env)
    if not owners:
        raise ValueError("TELEGRAM_ALLOWED_USERS must name at least one owner")

    request = find_request(arguments.database, owners, consumed_at())
    if request is None:
        print("hermes-secretary-bind: no unclaimed bind request")
        return
    control = control_for(request)
    if arguments.dry_run:
        print(json.dumps({"request": request, "control": control}, indent=2,
                         sort_keys=True))
        return
    write_control(control)
    write_text(CONSUMED, f"{request['timestamp']:.6f}\n")
    print(f"hermes-secretary-bind: desk bound to {control['desk_delivery']}")
    if not refresh(arguments.home):
        print("hermes-secretary-bind: reconcile script unavailable", file=sys.stderr)


if __name__ == "__main__":
    try:
        main()
    except (ValueError, OSError, KeyError, sqlite3.Error,
            subprocess.SubprocessError) as exc:
        print(f"hermes-secretary-bind failed: {exc}", file=sys.stderr)
        sys.exit(1)
