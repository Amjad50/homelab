#!/usr/bin/env python3
"""Cron entrypoint: refresh enabled prayer routines without a user notification."""

import contextlib
import io
import sys

import schedule

if __name__ == "__main__":
    sys.argv = ["schedule.py", "--reconcile"]
    with contextlib.redirect_stdout(io.StringIO()):
        schedule.main()
