# deploy.sh v2 — design

## Context

Deploying machines in this repo currently splits across two mechanisms that no longer
fit how the config works:

- **`deploy.sh`** archives `machines/$FLAKE_NAME/` + `common/` + `flake.nix`, ships it to
  the box, and (via `scripts/remote-deploy.sh`) copies docker-services to
  `/opt/docker-services`, writes config to `/etc/nixos`, and runs `nixos-rebuild`. It
  **cannot deploy configs that reuse another machine's files** (e.g. `middle-arm` imports
  `machines/middle` and its docker-services live under `machines/middle/docker-services` —
  the per-`$FLAKE_NAME` archive/copy misses them). This forced the recent OCI migration to
  bypass deploy.sh entirely and run `nixos-rebuild --target-host` by hand.
- Since then, **Nix now owns docker-services delivery**: the service registry gives each
  service a `source` (its compose dir, copied into the Nix store), and the
  `docker-compose-<svc>` unit rsyncs that store dir to `/opt/docker-services/<svc>` on
  activation, with `restartTriggers` so a `nixos-rebuild switch` restarts only services
  whose files changed. So a full system rebuild already deploys docker correctly,
  including for reused configs.

This makes the old deploy.sh both broken (reused configs) and partly redundant (it copies
docker files that Nix now manages). The goal: rework `deploy.sh` so a normal deploy is a
single Nix-driven command that handles everything, while keeping a fast no-Nix path for
iterating on compose files, and removing the per-machine archive surgery.

Pain points to fix (from the user):
1. System update should prefer Nix on the laptop, fall back to building on the box, all
   selectable by flag; rsync the **whole repo to a temp dir**, never `/etc/nixos`.
2. `--update` should cover both Nix (`flake update`) and docker (image pull).
3. A fast docker-only deploy that works despite `/opt/docker-services` being group
   read-only today (the user is in `docker` group but can't write the dirs).
4. Automate the `git add -fN secrets.yaml` / `git reset` dance.

## Model

Two non-overlapping modes:

| Mode | Runs Nix? | Who delivers docker files |
|------|-----------|---------------------------|
| **default (full)** | yes — `nixos-rebuild switch` | **Nix** (store → `/opt/docker-services` rsync on activation). deploy.sh never copies docker files. |
| **`--only-docker` (fast)** | **no** | **deploy.sh** — uploads compose files + restarts only changed services. The one place deploy.sh touches docker files directly. |

There is no `--no-docker` flag: a full rebuild always includes docker because Nix manages
it as part of the system config; you cannot meaningfully skip it.

## CLI surface

```
./deploy.sh <machine> [server] [options]

  <machine>            flake name (home, middle, middle-arm, ...)
  [server]             SSH target; omit = deploy to localhost

  --only-docker        Fast path: NO nix. Upload compose files + restart changed services.
  --update             flake update (nix path) AND docker image pull for (re)started
                       services (both paths, as relevant).
  --secrets <machine>  Which machine's secrets.yaml to git-expose for the build
                       (default: <machine>; e.g. `middle` for middle-arm). NIX PATH ONLY.
  --docker-from <m>    Which machine's docker-services to upload in --only-docker
                       (default: <machine>; `middle` for middle-arm). FAST PATH ONLY.
  --strategy <s>       nix-here | on-machine  (default: auto). NIX PATH ONLY.
```

`--secrets` and `--docker-from` are kept distinct (each names what its path reuses) even
though they're used in mutually exclusive paths.

## Full path — build strategy resolution

```
--strategy auto (default):
  1. local `nixos-rebuild` present  → nix-here
  2. else local `nix` present       → nix-here (via `nix run`)
  3. else                           → on-machine
--strategy nix-here     → force nix-here (error if neither nixos-rebuild nor nix locally)
--strategy on-machine   → force building on the box even if nix is available locally
```

**nix-here** (laptop drives the build; build happens on `--build-host`):
```
nixos-rebuild switch --flake .#<machine> \
  --target-host <server> --build-host <server> --sudo
```
- `nix run` variant uses **the flake's own nixpkgs input** (not the registry) for version
  consistency: `nix run <flake-nixpkgs>#nixos-rebuild -- switch ...` (resolve the nixpkgs
  store path / flake ref from this flake's lock).
- If `server` omitted (localhost): drop `--target-host`/`--build-host`; run with sudo
  locally.

**on-machine** (fallback or forced):
```
rsync whole repo (exclude .git, result, *.backup) → /tmp/nixos-deploy-<ts>/ on box
ssh <server> "cd <tmp> && sudo nixos-rebuild switch --flake .#<machine>"
remove temp dir afterward (trap)
```
- Whole-repo (not per-machine archive) so reused configs and all relative paths resolve.
- Never writes `/etc/nixos`.

## Full path — secrets dance

Wrap the Nix build:
```
git add -fN machines/<--secrets|machine>/secrets.yaml      # intent-to-add → git-visible to flake
trap 'git reset -q machines/<...>/secrets.yaml' EXIT       # always restore, even on failure/abort
... run nixos-rebuild (nix-here or on-machine) ...
```
- Only the nix path needs this (the fast path doesn't build).
- The `trap` guarantees the working tree never stays with secrets staged.

## Fast path — `--only-docker`

No Nix. deploy.sh delivers compose files itself:
```
1. src = machines/<--docker-from|machine>/docker-services/
2. per service dir: checksum-compare vs /opt/docker-services/<svc>; mark changed/new
3. upload (rsync) changed/new service dirs to /opt/docker-services/<svc>
   - localhost: rsync locally; remote: rsync over SSH
   - relies on §perms (2775 group-writable) so the docker-group user writes without sudo
4. for each CHANGED service only: (if --update) docker compose pull; then docker compose up -d
5. report changed/restarted services
```
- Restart scope: **only changed services** (checksum-compare), reusing the detection
  approach already in `scripts/remote-deploy.sh`.

## Nix module change — group-writable compose dirs

`common/modules/compose-services.nix` tmpfiles: bump mode `0755` → **`2775`** (setgid +
group-writable) on the root and each per-service dir:
```nix
[ "d ${composeRoot} 2775 dock docker - -" ]
++ map (s: "d ${composeRoot}/${s} 2775 dock docker - -") services;
```
- setgid → files created under it inherit the `docker` group.
- Lets a `docker`-group user edit/rsync compose files without sudo (enables the fast
  path's rsync and manual editing). `docker` group is already root-equivalent, so this is
  not a meaningful new exposure.

## Out of scope

- `scripts/remote-deploy.sh`: the on-machine strategy no longer needs the bespoke
  archive+copy script (it just rsyncs the repo and runs `nixos-rebuild` over SSH). It can
  be removed once deploy.sh v2 is verified, but removal is not required by this design.
- No change to the Nix `source`/`restartTriggers` mechanism (already shipped).
- Old middle retirement / backups untouched.

## Critical files

- `deploy.sh` — rewritten around the two-mode model + strategy resolver + secrets trap.
- `common/modules/compose-services.nix` — tmpfiles `0755` → `2775`.
- `scripts/remote-deploy.sh` — likely obsolete (removal optional, post-verification).

## Verification

1. **Full nix-here, localhost-less remote:** `./deploy.sh middle-arm <oci> --secrets middle`
   → builds via nix on the box, `/opt/docker-services` populated by Nix, services up,
   `idm.home.amsh.dev` serves a valid cert.
2. **Selective restart still holds:** change one service's compose, full deploy, confirm
   only that `docker-compose-<svc>` restarted.
3. **Forced on-machine:** `./deploy.sh home <home> --strategy on-machine` → rsyncs repo to
   a temp dir on the box, builds there, no `/etc/nixos` writes, temp cleaned up.
4. **Fast path:** edit a compose file, `./deploy.sh middle <m> --only-docker` → uploads +
   restarts only the changed service, **no nix run**, succeeds without sudo on the box
   (proves the 2775 perms).
5. **--update both ways:** full deploy `--update` bumps flake; `--only-docker --update`
   pulls images for restarted services.
6. **Secrets trap:** abort a build mid-run; confirm `git status` shows secrets.yaml NOT
   staged afterward.
7. **2775 perms live:** after a switch, `stat -c '%a' /opt/docker-services/<svc>` = 2775,
   and a docker-group user can `touch` a file there without sudo.
