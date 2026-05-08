#!/usr/bin/env bash
# homelab-restore — backup group restore CLI
# Reads /etc/homelab/services.json for group metadata.
# Injected env vars: HOMELAB_MACHINE, HOMELAB_LOCK, HOMELAB_REPO,
#   HOMELAB_RESTIC_PASSWORD_FILE, HOMELAB_RESTIC_S3_ENV

set -euo pipefail

META=/etc/homelab/services.json
[[ -f $META ]] || { echo "ERROR: $META not found" >&2; exit 1; }

: "${HOMELAB_MACHINE:?HOMELAB_MACHINE not set}"
: "${HOMELAB_LOCK:?HOMELAB_LOCK not set}"
: "${HOMELAB_REPO:?HOMELAB_REPO not set}"
: "${HOMELAB_RESTIC_PASSWORD_FILE:?HOMELAB_RESTIC_PASSWORD_FILE not set}"
: "${HOMELAB_RESTIC_S3_ENV:?HOMELAB_RESTIC_S3_ENV not set}"

COMPOSE_ROOT=/opt/docker-services

export RESTIC_REPOSITORY="$HOMELAB_REPO"
export RESTIC_PASSWORD_FILE="$HOMELAB_RESTIC_PASSWORD_FILE"
set -a
# shellcheck disable=SC1090
. "$HOMELAB_RESTIC_S3_ENV"
set +a

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; BLUE='\033[0;34m'; NC='\033[0m'
log()  { echo -e "${BLUE}[$(date -Iseconds)]${NC} $*"; }
ok()   { echo -e "${GREEN}✓${NC} $*"; }
warn() { echo -e "${YELLOW}!${NC} $*"; }
err()  { echo -e "${RED}✗${NC} $*" >&2; }

group_names()      { jq -r '.backups | keys[]' "$META"; }
group_exists()     { jq -e --arg g "$1" '.backups[$g] != null' "$META" >/dev/null; }
group_sentinel()   { jq -r --arg g "$1" '.backups[$g].sentinel' "$META"; }
group_postscript() { jq -r --arg g "$1" '.backups[$g].postRestoreScript // ""' "$META"; }
group_autostart()  { jq -e --arg g "$1" '.backups[$g].autoStart == true' "$META" >/dev/null; }
group_postgres()   { jq -c --arg g "$1" '.backups[$g].postgres // []' "$META"; }
group_services()   { jq -r --arg g "$1" '.backups[$g].composeServices[]?' "$META"; }

# ---------------------------------------------------------------------------
# restore_postgres — restore all postgres DBs for a group.
# Dump files must already be present in /tmp/db-dumps/<group>/ (from restic restore).
# Starts each DB container, waits for readiness, drops+recreates+imports.
# ---------------------------------------------------------------------------
restore_postgres() {
  local group="$1"
  local pg_entries
  pg_entries=$(group_postgres "$group")

  local count
  count=$(echo "$pg_entries" | jq 'length')
  (( count > 0 )) || return 0

  log "[${group}] Restoring ${count} postgres database(s)"

  local failed=0
  while IFS= read -r entry; do
    local stack compose_svc container database user dump_file
    stack=$(echo "$entry"        | jq -r '.stack')
    compose_svc=$(echo "$entry"  | jq -r '.composeService')
    container=$(echo "$entry"    | jq -r '.container')
    database=$(echo "$entry"     | jq -r '.database')
    user=$(echo "$entry"         | jq -r '.user')
    dump_file="/tmp/db-dumps/${group}/${database}.sql"

    if [[ ! -f $dump_file ]]; then
      err "[${group}] Dump file not found: ${dump_file} — skipping ${database}"
      failed=$((failed + 1))
      continue
    fi

    log "[${group}] Starting ${compose_svc} in stack ${stack}"
    (cd "${COMPOSE_ROOT}/${stack}" && docker compose up -d "$compose_svc") \
      || { err "[${group}] Failed to start ${compose_svc}"; failed=$((failed + 1)); continue; }

    log "[${group}] Waiting for postgres in ${container}..."
    local retries=30
    until docker exec "$container" pg_isready -U "$user" -d postgres -q 2>/dev/null; do
      retries=$((retries - 1))
      if (( retries <= 0 )); then
        err "[${group}] Timed out waiting for ${container} — skipping ${database}"
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

    local pg_rc=0
    docker exec "$container" psql -U "$user" postgres -q \
      -c "DROP DATABASE IF EXISTS \"${database}\";" \
      -c "CREATE DATABASE \"${database}\" OWNER \"${user}\";" || pg_rc=$?
    if (( pg_rc != 0 )); then
      err "[${group}] Failed to recreate database ${database}"
      failed=$((failed + 1))
      continue
    fi

    pg_rc=0
    docker exec -i "$container" psql -U "$user" -d "$database" -q < "$dump_file" || pg_rc=$?
    if (( pg_rc != 0 )); then
      err "[${group}] psql import failed for ${database} (exit ${pg_rc})"
      failed=$((failed + 1))
      continue
    fi

    ok "[${group}] ${database} restored"
  done < <(echo "$pg_entries" | jq -c '.[]')

  if (( failed > 0 )); then
    err "[${group}] ${failed}/${count} postgres restore(s) failed"
    return 1
  fi
  return 0
}

# ---------------------------------------------------------------------------
# restore_group — full restore:
#   1. Stop all group compose services
#   2. restic file restore (includes SQL dumps in /tmp/db-dumps/<group>/)
#   3. Start each DB container, restore postgres, stop DB container
#   4. Run postRestoreScript
#   5. Write sentinel
#   6. Start all group compose services (systemd will bring up full stacks)
# ---------------------------------------------------------------------------
restore_group() {
  local group="$1"
  local sentinel
  sentinel=$(group_sentinel "$group")

  log "[${group}] Stopping group services"
  compose-manage stop-group "$group"

  # Restic file restore (lands SQL dumps + all data files)
  log "[${group}] Acquiring lock and running restic restore"
  local restic_rc=0
  flock -x -w 21600 "$HOMELAB_LOCK" restic restore latest \
        --tag "group-${group}",backup-v2,"machine-${HOMELAB_MACHINE}" \
        --target / 2>&1 | sed "s/^/  [${group}] /" || restic_rc=$?
  if (( restic_rc != 0 )); then
    err "[${group}] restic restore failed (exit ${restic_rc})"
    return 1
  fi

  # Restore postgres databases
  restore_postgres "$group" || return 1

  # Post-restore script
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
      err "[${group}] postRestoreScript failed (exit ${post_rc})"
      return 1
    fi
  fi

  # Write sentinel
  mkdir -p "$(dirname "$sentinel")"
  touch "$sentinel"
  ok "[${group}] Restore complete — sentinel written to ${sentinel}"

  log "[${group}] Starting group services"
  compose-manage start-group "$group"

  return 0
}

cmd_list() {
  echo "Backup groups on machine '${HOMELAB_MACHINE}':"
  while read -r group; do
    local sentinel restored last autostart pg_count
    sentinel=$(group_sentinel "$group")
    restored="no"
    [[ -f $sentinel ]] && restored="yes ($(stat -c %y "$sentinel" | cut -d. -f1))"
    local snap_json snap_time snap_id last
    snap_json=$(restic snapshots latest --json \
        --tag "group-${group}",backup-v2,"machine-${HOMELAB_MACHINE}" \
        2>/dev/null | jq -r '.[-1] // empty' 2>/dev/null || true)
    snap_time=$(echo "$snap_json" | jq -r '.time  // "never"' 2>/dev/null || echo "never")
    snap_id=$(  echo "$snap_json" | jq -r '.short_id // ""'   2>/dev/null || true)
    last="${snap_time}${snap_id:+ (${snap_id})}"
    autostart="autoStart"
    group_autostart "$group" || autostart="manual"
    pg_count=$(group_postgres "$group" | jq 'length')
    printf "  %-20s restored=%-35s last=%s [%s] [%d postgres]\n" \
      "$group" "$restored" "$last" "$autostart" "$pg_count"
  done < <(group_names)
}

cmd_group() {
  local group="${1:-}"
  [[ -n $group ]] || { err "Usage: homelab-restore group <name>"; exit 2; }
  group_exists "$group" || { err "Group '$group' not found in $META"; exit 2; }
  restore_group "$group"
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
  ok  "Succeeded (${#succeeded[@]}): ${succeeded[*]:-<none>}"
  if (( ${#failed[@]} > 0 )); then
    err "Failed (${#failed[@]}): ${failed[*]}"
    exit 1
  fi
}

case "${1:-}" in
  list)             shift; cmd_list "$@" ;;
  group)            shift; cmd_group "$@" ;;
  all)              shift; cmd_all "$@" ;;
  ""|--help|-h)
    cat <<EOF
homelab-restore — backup group restore CLI

Usage:
  homelab-restore list
      Show all backup groups, last backup time, and restore status.

  homelab-restore group <name>
      Full restore of a single backup group:
        1. Stop all compose services in the group
        2. restic restore (files + SQL dumps)
        3. Start DB containers, restore postgres databases
        4. Run postRestoreScript (if any)
        5. Write sentinel file
        6. Start all group services

  homelab-restore all
      Restore every backup group sequentially.
EOF
    ;;
  *)
    err "Unknown subcommand: ${1}"; exit 2 ;;
esac
