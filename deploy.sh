#!/usr/bin/env bash

# Usage: ./deploy.sh <machine> [server] [options]
#
#   <machine>            flake name (home, middle, ...)
#   [server]             SSH target (user@host); omit = deploy to localhost
#
#   --only-docker        Fast path: NO nix. Upload compose files + restart changed services.
#   --update             flake update (nix path) AND docker image pull (both paths).
#   --secrets <machine>  Which machine's secrets.yaml to git-expose for the build
#                        (default: <machine>; override for configs that reuse another
#                        machine's secrets). Nix path only.
#   --docker-from <m>    Which machine's docker-services to upload in --only-docker
#                        (default: <machine>). Fast path only.
#   --strategy <s>       nix-here | on-machine  (default: auto). Nix path only.

set -e

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
BLUE='\033[0;34m'; PURPLE='\033[0;35m'; CYAN='\033[0;36m'; NC='\033[0m'

log_info()    { echo -e "${BLUE}[INFO]${NC} $1"; }
log_success() { echo -e "${GREEN}[SUCCESS]${NC} $1"; }
log_warn()    { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error()   { echo -e "${RED}[ERROR]${NC} $1"; }
log_step()    { echo -e "${PURPLE}[STEP]${NC} $1"; }
log_docker()  { echo -e "${CYAN}[DOCKER]${NC} $1"; }

usage() { sed -n '3,15p' "$0"; }

# ---- args ----------------------------------------------------------------

MACHINE=""
SERVER=""
ONLY_DOCKER=false
UPDATE=false
SECRETS_FROM=""
DOCKER_FROM=""
STRATEGY="auto"

# Require a value for a flag taking an argument; reject missing/another-flag values.
need_val() { # $1=flag name, $2=value
    case "${2-}" in
        ""|-*) log_error "$1 requires a value"; usage; exit 1 ;;
    esac
}

while [ $# -gt 0 ]; do
    case "$1" in
        --only-docker) ONLY_DOCKER=true; shift ;;
        --update)      UPDATE=true; shift ;;
        --secrets)     need_val "$1" "${2-}"; SECRETS_FROM="$2"; shift 2 ;;
        --docker-from) need_val "$1" "${2-}"; DOCKER_FROM="$2"; shift 2 ;;
        --strategy)    need_val "$1" "${2-}"; STRATEGY="$2"; shift 2 ;;
        -h|--help)     usage; exit 0 ;;
        -*)            log_error "Unknown flag: $1"; usage; exit 1 ;;
        *)
            if   [ -z "$MACHINE" ]; then MACHINE="$1"
            elif [ -z "$SERVER" ];  then SERVER="$1"
            else log_error "Unexpected argument: $1"; exit 1
            fi
            shift ;;
    esac
done

[ -n "$MACHINE" ] || { log_error "Missing <machine>"; usage; exit 1; }

case "$STRATEGY" in
    auto|nix-here|on-machine) ;;
    *) log_error "--strategy must be auto | nix-here | on-machine (got: $STRATEGY)"; exit 1 ;;
esac

SECRETS_FROM="${SECRETS_FROM:-$MACHINE}"
DOCKER_FROM="${DOCKER_FROM:-$MACHINE}"

REPO_ROOT="$(cd "$(dirname "$0")" && pwd)"
cd "$REPO_ROOT"

# ---- helpers -------------------------------------------------------------

# Run a command string on the target (remote via ssh, or locally).
run_target() {
    if [ -n "$SERVER" ]; then ssh "$SERVER" "$1"; else bash -c "$1"; fi
}

# Directory content checksum (filenames + contents). $1 = dir.
dir_cksum_cmd() {
    printf 'find %q -type f -printf "%%P\\n" -exec sha256sum {} \\; 2>/dev/null | sort | sha256sum | cut -d" " -f1' "$1"
}

# ---- fast path: --only-docker (no nix) -----------------------------------

deploy_docker_only() {
    local src="machines/$DOCKER_FROM/docker-services"
    [ -d "$src" ] || { log_error "No docker-services dir at $src"; exit 1; }

    log_step "Fast docker deploy from $src (no nix)"
    local changed=()
    local sdir name newck oldck
    for sdir in "$src"/*/; do
        [ -d "$sdir" ] || continue
        name="$(basename "$sdir")"
        newck="$(bash -c "$(dir_cksum_cmd "$sdir")")"
        oldck="$(run_target "$(dir_cksum_cmd "/opt/docker-services/$name")" 2>/dev/null || echo MISSING)"
        if [ "$newck" != "$oldck" ]; then
            log_docker "changed: $name"
            changed+=("$name")
        fi
    done

    if [ ${#changed[@]} -eq 0 ]; then
        log_success "No docker-services changes; nothing to do."
        return 0
    fi

    for name in "${changed[@]}"; do
        log_docker "uploading: $name"
        if [ -n "$SERVER" ]; then
            rsync -a --delete "$src/$name/" "$SERVER:/opt/docker-services/$name/"
        else
            rsync -a --delete "$src/$name/" "/opt/docker-services/$name/"
        fi
    done

    # Up the changed services directly in /opt/docker-services (NOT `compose-manage
    # restart`, which does `systemctl restart` — that unit's ExecStartPre re-rsyncs the
    # nix-store copy over our just-uploaded files, clobbering the fast-path edits).
    for name in "${changed[@]}"; do
        log_docker "up -d: $name"
        run_target "cd /opt/docker-services/$name && sudo -u dock docker compose up -d --remove-orphans" \
            || log_warn "up -d failed: $name"
    done

    log_success "Fast docker deploy complete: ${changed[*]}"
}

# Pull newer images for ALL services and restart running ones. Image updates are a
# fleet-wide concern (independent of which compose files changed), and the same
# regardless of nix/no-nix. Uses the on-box compose-manage wrapper.
docker_pull_all() {
    log_docker "compose-manage pull --up (all services)"
    run_target "compose-manage pull --up" || log_warn "image pull failed"
}

# ---- full path: nix ------------------------------------------------------

resolve_strategy() {
    if [ "$STRATEGY" != "auto" ]; then echo "$STRATEGY"; return; fi
    if command -v nixos-rebuild >/dev/null 2>&1; then echo nix-here; return; fi
    if command -v nix          >/dev/null 2>&1; then echo nix-here; return; fi
    echo on-machine
}

# Invoke nixos-rebuild: prefer the binary, else `nix run nixpkgs#nixos-rebuild`.
nixos_rebuild() {
    if command -v nixos-rebuild >/dev/null 2>&1; then
        nixos-rebuild "$@"
    else
        nix run nixpkgs#nixos-rebuild -- "$@"
    fi
}

build_nix_here() {
    [ "$UPDATE" = true ] && nix flake update --flake "$REPO_ROOT"
    local args=(switch --install-bootloader --flake "$REPO_ROOT#$MACHINE")
    if [ -n "$SERVER" ]; then
        # --use-remote-sudo: works across the nixos-rebuild versions our `nix run`
        # resolves (older ones lack --sudo). Remote activation runs via sudo on the box.
        args+=(--target-host "$SERVER" --build-host "$SERVER" --use-remote-sudo)
        log_step "nixos-rebuild ${args[*]}"
        nixos_rebuild "${args[@]}"
    else
        # localhost: activation needs root locally.
        log_step "sudo nixos-rebuild ${args[*]}"
        if command -v nixos-rebuild >/dev/null 2>&1; then
            sudo nixos-rebuild "${args[@]}"
        else
            sudo nix run nixpkgs#nixos-rebuild -- "${args[@]}"
        fi
    fi
}

build_on_machine() {
    [ -n "$SERVER" ] || { log_error "--strategy on-machine requires a [server]"; exit 1; }
    local tmp
    tmp="/tmp/nixos-deploy-$(date +%s)"
    log_step "rsync repo -> $SERVER:$tmp (build on box)"
    ssh "$SERVER" "mkdir -p '$tmp'"
    # Copy exactly the git-tracked set (incl. the secrets.yaml exposed via `git add -fN`
    # in deploy_full) and nothing gitignored — skips qcow2 disk images, machines/tests/,
    # result dirs, etc. Authoritative match for what the flake build sees.
    rsync -a --files-from=<(git -C "$REPO_ROOT" ls-files) \
        "$REPO_ROOT"/ "$SERVER:$tmp/"
    local upd=""
    [ "$UPDATE" = true ] && upd="sudo nix flake update --flake '$tmp'; "
    log_step "nixos-rebuild switch on $SERVER"
    # shellcheck disable=SC2029  # intentional remote-side expansion of $tmp/$MACHINE
    ssh -t "$SERVER" "${upd}sudo nixos-rebuild switch --install-bootloader --flake '$tmp#$MACHINE'; rc=\$?; rm -rf '$tmp'; exit \$rc"
}

deploy_full() {
    local secrets="machines/$SECRETS_FROM/secrets.yaml"
    if [ -f "$secrets" ]; then
        log_info "Exposing $secrets to git for the build"
        git add -fN "$secrets"
        # shellcheck disable=SC2064  # expand $secrets now, on trap install
        trap "git reset -q '$secrets' 2>/dev/null || true" EXIT
    else
        log_warn "No secrets file at $secrets (skipping secrets expose)"
    fi

    local strat; strat="$(resolve_strategy)"
    log_info "Build strategy: $strat"
    case "$strat" in
        nix-here)   build_nix_here ;;
        on-machine) build_on_machine ;;
    esac
    log_success "Deploy complete ($MACHINE via $strat)"
}

# ---- dispatch ------------------------------------------------------------

[ -n "$SERVER" ] && log_info "Target: $SERVER" || log_info "Target: localhost"

if [ "$ONLY_DOCKER" = true ]; then
    deploy_docker_only
    [ "$UPDATE" = true ] && docker_pull_all
else
    deploy_full
    [ "$UPDATE" = true ] && docker_pull_all
fi
