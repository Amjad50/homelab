#!/usr/bin/env bash
# restore-backup — backup group restore CLI
# Reads /etc/homelab/services.json for group metadata.
# Injected env vars: HOMELAB_MACHINE, HOMELAB_LOCK, HOMELAB_REPO,
#   HOMELAB_RESTIC_PASSWORD_FILE, HOMELAB_RESTIC_S3_ENV

set -euo pipefail

source /etc/homelab/lib.sh

require_meta
for v in HOMELAB_MACHINE HOMELAB_LOCK HOMELAB_REPO HOMELAB_RESTIC_PASSWORD_FILE HOMELAB_RESTIC_S3_ENV; do
  require_env "$v"
done

export RESTIC_REPOSITORY="$HOMELAB_REPO"
export RESTIC_PASSWORD_FILE="$HOMELAB_RESTIC_PASSWORD_FILE"
set -a
# shellcheck disable=SC1090
. "$HOMELAB_RESTIC_S3_ENV"
set +a

# --- Postgres restore ---

restore_postgres() {
  local group=$1
  local pg_entries
  pg_entries=$(group_postgres "$group")

  local count
  count=$(echo "$pg_entries" | jq 'length')
  (( count > 0 )) || return 0

  log "[${group}] Restoring ${count} postgres database(s)"

  local failed=0
  while IFS= read -r entry; do
    local stack compose_svc container database user dump_file
    stack=$(jq_field "$entry" stack)
    compose_svc=$(jq_field "$entry" composeService)
    container=$(jq_field "$entry" container)
    database=$(jq_field "$entry" database)
    user=$(jq_field "$entry" user)
    dump_file="/tmp/db-dumps/${group}/${database}.sql"

    if [[ ! -f $dump_file ]]; then
      log_err "[${group}] Dump file not found: ${dump_file} — skipping ${database}"
      failed=$((failed + 1))
      continue
    fi

    log "[${group}] Starting ${compose_svc} in stack ${stack}"
    if ! (cd "${COMPOSE_ROOT}/${stack}" && docker compose up -d "$compose_svc"); then
      log_err "[${group}] Failed to start ${compose_svc}"
      failed=$((failed + 1))
      continue
    fi

    log "[${group}] Waiting for postgres in ${container}..."
    local retries=30
    until docker exec "$container" pg_isready -U "$user" -d postgres -q 2>/dev/null; do
      retries=$((retries - 1))
      if (( retries <= 0 )); then
        log_err "[${group}] Timed out waiting for ${container} — skipping ${database}"
        failed=$((failed + 1))
        break
      fi
      sleep 3
    done
    (( retries > 0 )) || continue

    log "[${group}] Restoring ${database} in ${container}"

    # Terminate existing connections before dropping
    docker exec "$container" psql -U "$user" postgres -q -c "
      SELECT pg_terminate_backend(pid)
      FROM pg_stat_activity
      WHERE datname = '${database}' AND pid <> pg_backend_pid();
    " >/dev/null 2>&1 || true

    if ! docker exec "$container" psql -U "$user" postgres -q \
      -c "DROP DATABASE IF EXISTS \"${database}\";" \
      -c "CREATE DATABASE \"${database}\" OWNER \"${user}\";"; then
      log_err "[${group}] Failed to recreate database ${database}"
      failed=$((failed + 1))
      continue
    fi

    local pg_rc=0
    docker exec -i "$container" psql -U "$user" -d "$database" -q < "$dump_file" || pg_rc=$?
    if (( pg_rc != 0 )); then
      log_err "[${group}] psql import failed for ${database} (exit ${pg_rc})"
      failed=$((failed + 1))
      continue
    fi

    log_ok "[${group}] ${database} restored"
  done < <(echo "$pg_entries" | jq -c '.[]')

  if (( failed > 0 )); then
    log_err "[${group}] ${failed}/${count} postgres restore(s) failed"
    return 1
  fi
}

# --- Group restore ---

restore_group() {
  local group=$1
  local sentinel
  sentinel=$(group_sentinel "$group")

  log "[${group}] Stopping group services"
  compose-manage stop-group "$group"

  log "[${group}] Acquiring lock and running restic restore"
  local restic_rc=0
  flock -x -w 21600 "$HOMELAB_LOCK" restic restore latest \
        --tag "group-${group}",backup-v2,"machine-${HOMELAB_MACHINE}" \
        --target / 2>&1 | sed "s/^/  [${group}] /" || restic_rc=$?
  if (( restic_rc != 0 )); then
    log_err "[${group}] restic restore failed (exit ${restic_rc})"
    return 1
  fi

  restore_postgres "$group" || return 1

  local script
  script=$(group_postscript "$group")
  if [[ -n $script ]]; then
    log "[${group}] Running postRestoreScript"
    local tmp
    tmp=$(mktemp)
    trap 'rm -f "$tmp"' RETURN
    printf '%s\n' "$script" > "$tmp"
    local post_rc=0
    bash "$tmp" 2>&1 | sed "s/^/  [${group}] /" || post_rc=$?
    if (( post_rc != 0 )); then
      log_err "[${group}] postRestoreScript failed (exit ${post_rc})"
      return 1
    fi
  fi

  mkdir -p "$(dirname "$sentinel")"
  touch "$sentinel"
  log_ok "[${group}] Restore complete — sentinel written to ${sentinel}"

  log "[${group}] Starting group services"
  compose-manage start-group "$group"
}

# --- Commands ---

cmd_list() {
  echo "Backup groups on machine '${HOMELAB_MACHINE}':"
  while read -r group; do
    local sentinel restored snap_json snap_time snap_id last autostart pg_count
    sentinel=$(group_sentinel "$group")
    restored="no"
    [[ -f $sentinel ]] && restored="yes ($(stat -c %y "$sentinel" | cut -d. -f1))"

    snap_json=$(restic snapshots latest --json \
        --tag "group-${group}",backup-v2,"machine-${HOMELAB_MACHINE}" \
        2>/dev/null | jq -r '.[-1] // empty' 2>/dev/null || true)
    snap_time=$(jq_field "$snap_json" 'time  // "never"' 2>/dev/null || echo "never")
    snap_id=$(jq_field "$snap_json" 'short_id // ""' 2>/dev/null || true)
    last="${snap_time}${snap_id:+ (${snap_id})}"

    autostart="autoStart"
    group_autostart "$group" || autostart="manual"
    pg_count=$(group_postgres "$group" | jq 'length')
    printf "  %-20s restored=%-35s last=%s [%s] [%d postgres]\n" \
      "$group" "$restored" "$last" "$autostart" "$pg_count"
  done < <(group_names)
}

cmd_group() {
  require_arg "${1:-}" "restore-backup group <name>"
  require_group "$1"
  restore_group "$1"
}

cmd_all() {
  local -a groups
  mapfile -t groups < <(group_names)
  log "Restoring ${#groups[@]} backup group(s)"

  local -a succeeded=() failed=()
  for group in "${groups[@]}"; do
    if restore_group "$group"; then
      succeeded+=("$group")
    else
      failed+=("$group")
    fi
  done

  echo
  log "=== Restore summary ==="
  log_ok  "Succeeded (${#succeeded[@]}): ${succeeded[*]:-<none>}"
  if (( ${#failed[@]} > 0 )); then
    log_err "Failed (${#failed[@]}): ${failed[*]}"
    exit 1
  fi
}

# --- Main ---

case "${1:-}" in
  list)        cmd_list ;;
  group)       shift; cmd_group "$@" ;;
  all)         cmd_all ;;
  ""|--help|-h)
    cat <<EOF
restore-backup — backup group restore CLI

Usage:
  restore-backup list
      Show all backup groups, last backup time, and restore status.

  restore-backup group <name>
      Full restore of a single backup group:
        1. Stop all compose services in the group
        2. restic restore (files + SQL dumps)
        3. Start DB containers, restore postgres databases
        4. Run postRestoreScript (if any)
        5. Write sentinel file
        6. Start all group services

  restore-backup all
      Restore every backup group sequentially.
EOF
    ;;
  *)
    err "Unknown subcommand: ${1}"; exit 2 ;;
esac
