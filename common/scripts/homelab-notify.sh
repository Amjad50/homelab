#!/usr/bin/env sh
set -eu

env_file="${NTFY_ENV_FILE:-/var/lib/dock/ntfy-client.env}"
if [ -r "$env_file" ]; then
  # shellcheck disable=SC1090
  . "$env_file"
fi

ntfy_url="${NTFY_URL:-https://ntfy.home.amsh.dev}"
ntfy_topic="${NTFY_TOPIC:-homelab}"
ntfy_token="${NTFY_TOKEN:-}"

notify() {
  title="$1"
  priority="$2"
  tags="$3"
  message="$4"

  if [ -z "$ntfy_token" ]; then
    echo "homelab-notify: NTFY_TOKEN is not set; skipping" >&2
    return 0
  fi

  curl -fsS \
    -H "Authorization: Bearer ${ntfy_token}" \
    -H "Title: ${title}" \
    -H "Priority: ${priority}" \
    -H "Tags: ${tags}" \
    -d "$message" \
    "${ntfy_url%/}/${ntfy_topic}" >/dev/null || {
      echo "homelab-notify: ntfy publish failed" >&2
      return 0
    }
}

human_size() {
  bytes="${1:-0}"
  if command -v numfmt >/dev/null 2>&1; then
    numfmt --to=iec-i --suffix=B "$bytes" 2>/dev/null && return 0
  fi
  printf '%s bytes\n' "$bytes"
}

backup_message() {
  status="$1"
  group="$2"
  unit="restic-backups-${group}.service"
  host="$(hostname 2>/dev/null || printf 'home')"
  result="unknown"
  started="unknown"
  finished="unknown"

  if command -v systemctl >/dev/null 2>&1; then
    result="$(systemctl show "$unit" -p Result --value 2>/dev/null || printf unknown)"
    started="$(systemctl show "$unit" -p ExecMainStartTimestamp --value 2>/dev/null || printf unknown)"
    finished="$(systemctl show "$unit" -p ExecMainExitTimestamp --value 2>/dev/null || printf unknown)"
  fi

  {
    printf '%s backup on %s\n' "$group" "$host"
    printf 'Unit: %s\n' "$unit"
    printf 'Result: %s\n' "$result"
    [ -n "${started:-}" ] && [ "$started" != "unknown" ] && printf 'Started: %s\n' "$started"
    [ -n "${finished:-}" ] && [ "$finished" != "unknown" ] && printf 'Finished: %s\n' "$finished"
    backup_stats "$unit" "$status" "$result"
  }
}

strip_control() {
  awk '{
    gsub(/\033\[[0-9;?]*[ -\/]*[@-~]/, "")
    gsub(/[^[:print:]\t]/, "")
    print
  }'
}

clean_restic_line() {
  sed -E 's/[[:space:]]+/ /g; s/^ //; s/ $//'
}

format_dump_line() {
  clean_restic_line |
    sed -E 's/^.*\] Dumped /- /; s/ -> /: /; s/ → /: /'
}

backup_stats() {
  unit="$1"
  status="$2"
  result="$3"

  command -v journalctl >/dev/null 2>&1 || return 0

  log="$(
    journalctl -u "$unit" -n 300 --no-pager -o cat 2>/dev/null |
      strip_control |
      awk -v unit="$unit" '
        $0 == "Starting " unit "..." { out = "" }
        { out = out $0 "\n" }
        END { printf "%s", out }
      '
  )"

  [ -n "$log" ] || return 0

  if [ "$status" != "success" ]; then
    backup_failure_details "$unit" "$result" "$log"
    return 0
  fi

  snapshot_id="$(printf '%s\n' "$log" | awk '/^snapshot [[:xdigit:]]+ saved$/ { id = $2 } END { print id }')"
  resources="$(printf '%s\n' "$log" | awk -v unit="$unit" 'index($0, unit ": Consumed ") == 1 { line = $0 } END { print line }')"

  if [ -n "$snapshot_id" ] && restic_snapshot_summary "$snapshot_id"; then
    group="${unit#restic-backups-}"
    group="${group%.service}"
    restic_database_summary "$snapshot_id" "$group"
  else
    journal_backup_summary "$log"
  fi

  if [ -n "$resources" ]; then
    resources="${resources#"$unit: Consumed "}"
    printf '\nResources:\n%s\n' "$resources"
  fi

  if [ -z "$snapshot_id" ]; then
    printf '\nRecent log:\n'
    printf '%s\n' "$log" | tail -n 15
  fi
}

backup_failure_details() {
  unit="$1"
  result="$2"
  log="$3"

  printf '\nFailure details:\n'
  if [ "$result" = "success" ]; then
    printf 'No failed backup run found. Last %s result is success; this looks like a manual failure notification test.\n' "$unit"
    return 0
  fi

  error_line="$(printf '%s\n' "$log" | awk '
    /Fatal:|ERROR|Error:/ { line = $0 }
    END { print line }
  ')"
  if [ -z "$error_line" ]; then
    error_line="$(printf '%s\n' "$log" | awk '
      /Failed with result|Main process exited/ { line = $0 }
      END { print line }
    ')"
  fi
  [ -n "$error_line" ] && printf '%s\n' "$error_line"

  prepared="$(printf '%s\n' "$log" | awk '/Dumped .* \([^)]+\)$/ { print }')"
  if [ -n "$prepared" ]; then
    printf '\nPrepared databases:\n'
    printf '%s\n' "$prepared" | format_dump_line
  fi

  resources="$(printf '%s\n' "$log" | awk -v unit="$unit" 'index($0, unit ": Consumed ") == 1 { line = $0 } END { print line }')"
  if [ -n "$resources" ]; then
    resources="${resources#"$unit: Consumed "}"
    printf '\nResources:\n%s\n' "$resources"
  fi

  printf '\nRecent error log:\n'
  printf '%s\n' "$log" |
    awk '
      /^ID[[:space:]]+Time[[:space:]]+Host[[:space:]]+Tags/ { in_table = 1; next }
      in_table && /^-+$/ { next }
      in_table && /^[0-9a-f]{8}[[:space:]]/ { next }
      in_table && /^[[:space:]]+/ { next }
      in_table && /^[0-9]+ snapshots$/ { in_table = 0; next }
      /^Files:/ { next }
      /^Dirs:/ { next }
      /^Added to the repository:/ { next }
      /^processed / { next }
      /^snapshot [[:xdigit:]]+ saved$/ { next }
      /^Applying Policy:/ { next }
      /^keep [0-9]+ snapshots:/ { next }
      /^Finished / { next }
      /Deactivated successfully/ { next }
      { print }
    ' |
    tail -n 20
}

restic_default() {
  restic_cmd="${RESTIC_DEFAULT_COMMAND:-/run/current-system/sw/bin/restic-default}"

  if [ -x "$restic_cmd" ]; then
    "$restic_cmd" "$@"
  elif command -v restic-default >/dev/null 2>&1; then
    restic-default "$@"
  else
    return 127
  fi
}

restic_snapshot_summary() {
  snapshot_id="$1"

  command -v jq >/dev/null 2>&1 || return 1
  snapshot_json="$(restic_default snapshots "$snapshot_id" --json 2>/dev/null)" || return 1
  [ -n "$snapshot_json" ] || return 1

  printf '\nSummary:\n'
  printf '%s\n' "$snapshot_json" | jq -r '
    .[0] as $s
    | ($s.summary // {}) as $m
    | "Snapshot: \($s.short_id)",
      "When: \($s.time)",
      "Files: \($m.files_new // 0) new, \($m.files_changed // 0) changed, \($m.files_unmodified // 0) unmodified",
      "Dirs: \($m.dirs_new // 0) new, \($m.dirs_changed // 0) changed, \($m.dirs_unmodified // 0) unmodified",
      "Processed: \($m.total_files_processed // 0) files, \($m.total_bytes_processed // 0) bytes",
      "Added: \($m.data_added // 0) bytes (\($m.data_added_packed // 0) stored)"
  ' | while IFS= read -r line; do
    case "$line" in
      Processed:*)
        files="$(printf '%s\n' "$line" | awk '{ print $2 }')"
        bytes="$(printf '%s\n' "$line" | awk '{ print $4 }')"
        printf 'Processed: %s files, %s\n' "$files" "$(human_size "$bytes")"
        ;;
      Added:*)
        bytes="$(printf '%s\n' "$line" | awk '{ print $2 }')"
        stored="$(printf '%s\n' "$line" | awk -F'[()]' '{ print $2 }' | awk '{ print $1 }')"
        printf 'Added: %s (%s stored)\n' "$(human_size "$bytes")" "$(human_size "$stored")"
        ;;
      *)
        printf '%s\n' "$line"
        ;;
    esac
  done
}

restic_database_summary() {
  snapshot_id="$1"
  group="$2"

  command -v jq >/dev/null 2>&1 || return 0
  db_json="$(restic_default ls "$snapshot_id" --json "/tmp/db-dumps/$group" 2>/dev/null)" || return 0
  db_files="$(printf '%s\n' "$db_json" | jq -r 'select(.type == "file") | [.name, .size] | @tsv')" || return 0
  [ -n "$db_files" ] || return 0

  printf '\nDatabases:\n'
  printf '%s\n' "$db_files" | while IFS="$(printf '\t')" read -r name size; do
    name="${name%.sql}"
    printf -- '- %s: %s\n' "$name" "$(human_size "$size")"
  done
}

journal_backup_summary() {
  log="$1"

  files="$(printf '%s\n' "$log" | awk '/^Files:/ { line = $0 } END { print line }')"
  dirs="$(printf '%s\n' "$log" | awk '/^Dirs:/ { line = $0 } END { print line }')"
  added="$(printf '%s\n' "$log" | awk '/^Added to the repository:/ { line = $0 } END { print line }')"
  processed="$(printf '%s\n' "$log" | awk '/^processed / { line = $0 } END { print line }')"
  snapshot="$(printf '%s\n' "$log" | awk '/^snapshot [[:xdigit:]]+ saved$/ { line = $0 } END { print line }')"
  dumped="$(printf '%s\n' "$log" | awk '/Dumped .* \([^)]+\)$/ { print }')"

  printf '\nSummary:\n'
  [ -n "$snapshot" ] && printf '%s\n' "$(printf '%s\n' "$snapshot" | clean_restic_line)"
  [ -n "$processed" ] && printf '%s\n' "$(printf '%s\n' "$processed" | clean_restic_line)"
  [ -n "$added" ] && printf '%s\n' "$(printf '%s\n' "$added" | clean_restic_line)"
  [ -n "$files" ] && printf '%s\n' "$(printf '%s\n' "$files" | clean_restic_line)"
  [ -n "$dirs" ] && printf '%s\n' "$(printf '%s\n' "$dirs" | clean_restic_line)"

  if [ -n "$dumped" ]; then
    printf '\nDatabases:\n'
    printf '%s\n' "$dumped" | format_dump_line
  fi
}

backup_priority() {
  group="$1"

  if [ "$group" = "immich" ]; then
    printf 'high'
  else
    printf 'default'
  fi
}

backup_success_title() {
  group="$1"

  if [ "$group" = "immich" ]; then
    printf 'Important backup completed: %s' "$group"
  else
    printf 'Backup completed: %s' "$group"
  fi
}

backup_failure_title() {
  group="$1"

  if [ "$group" = "immich" ]; then
    printf 'Important backup failed: %s' "$group"
  else
    printf 'Backup failed: %s' "$group"
  fi
}

notify_backup() {
  status="$1"
  group="$2"

  if [ "$status" = "success" ]; then
    notify "$(backup_success_title "$group")" "$(backup_priority "$group")" "white_check_mark,floppy_disk" "$(backup_message "$status" "$group")"
  else
    notify "$(backup_failure_title "$group")" "high" "x,floppy_disk,warning" "$(backup_message "$status" "$group")"
  fi
}

notify_backup_all() {
  status="$1"

  if command -v systemctl >/dev/null 2>&1; then
    units="$(systemctl list-units 'restic-backups-*.service' --all --plain --no-legend 2>/dev/null | awk '{ print $1 }')"
    if [ -n "$units" ]; then
      printf '%s\n' "$units" | while IFS= read -r unit; do
        group="${unit#restic-backups-}"
        group="${group%.service}"
        notify_backup "$status" "$group"
      done
      return 0
    fi
  fi

  notify_backup "$status" default
}

case "${1:-}" in
  backup-success)
    notify_backup success "${2:-default}"
    ;;
  backup-failure)
    notify_backup failure "${2:-default}"
    ;;
  backup-success-all)
    notify_backup_all success
    ;;
  backup-failure-all)
    notify_backup_all failure
    ;;
  torrent-complete)
    name="${2:-${QBT_NAME:-Unknown torrent}}"
    size="$(human_size "${3:-${QBT_SIZE:-0}}")"
    notify "Download complete" "low" "arrow_down" "$(printf '%s\n%s' "$name" "$size")"
    ;;
  test)
    notify "Homelab notification test" "default" "bell" "Test notification from $(hostname 2>/dev/null || printf home)"
    ;;
  *)
    cat >&2 <<'USAGE'
Usage:
  homelab-notify backup-success <group>
  homelab-notify backup-failure <group>
  homelab-notify backup-success-all
  homelab-notify backup-failure-all
  homelab-notify torrent-complete <name> <size-bytes>
  homelab-notify test
USAGE
    exit 64
    ;;
esac
