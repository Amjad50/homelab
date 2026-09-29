# Hermes secretary staging and owner setup

Pinned Hermes: `9fe737aef2dd18a351dff3c4de608d63879a6524` (`flake.lock`).
This repository stages a private local organizer and three skills. Native Hermes
cron is available to authenticated Telegram and CLI sessions for explicitly
requested reminders.

Desk delivery identity is never configured and never taken from model text or a
topic title. It is read from the gateway's own authenticated session records by
`hermes-secretary-bind`, and only when the owner sends an explicit bind request
in the target topic. Nothing binds on its own. Google/Jira writes, topic routing
beyond the bound Desk target, and Sol calls are not activated.

## Build and deployment

From the repository root:

```sh
nix eval --json .#nixosConfigurations.home.config.microvm.vms.hermes.config.config.services.hermes-agent.settings
nix build .#hermes-vm --no-link
git add -fN machines/home/secrets.yaml
nix build .#nixosConfigurations.home.config.system.build.toplevel --no-link
git reset -q machines/home/secrets.yaml
./deploy.sh home amjad@home --strategy nix-here
```

The `git add -fN` step temporarily exposes the encrypted sops file to Nix,
as `deploy.sh` does; `git reset` removes that intent-to-add state. The final
command switches the host and restarts the VM; run it only after deployment
authorization. The local SSH config supplies `home` as the host.
To roll back the host generation:

```sh
ssh -t amjad@home 'sudo nixos-rebuild switch --rollback'
ssh -t amjad@home 'sudo systemctl restart microvm@hermes.service'
```

Rollback does not reverse organizer data. Preserve `/var/lib/hermes` and
`/var/lib/hermes-organizer/data` inside the VM before any destructive restore.
Current host restic groups do not include the Hermes VM's state disk; backup
and restore coverage are not yet established.

## Desk binding and routine activation

Nothing binds automatically. To create the Desk destination, run the skill
command in the topic that should receive reminders:

```text
/desk-setup
```

The plain text `desk setup` (`setup desk`, `bind-desk`, and `bind desk` too) is
matched the same way, which is the fallback if the command is ever unavailable.
The skill exists so the command is recognized; it deliberately cannot perform
the binding, and its body tells the model not to try.

`hermes-secretary-bind` wakes on a one-minute timer, finds the newest unclaimed
request from the owner in the gateway's `state.db`, and reads the chat and
thread identifiers from that session record. Slash commands are dispatched by
the gateway rather than stored as raw text, so an invocation is matched through
the scaffold the pinned revision records for it; the scaffold carries the same
trusted session. The chat and thread an agent reports in conversation are never
used, so a prompt-injected page or a quoted identifier cannot redirect delivery.
A request whose session has no topic, or that comes from anyone other than an
allowed owner, is ignored.

The consumed request is recorded in `/var/lib/hermes-organizer/.desk-bind-consumed`,
so an old command can never re-point delivery at a different topic later. The
control file `/var/lib/hermes-organizer/cron-control.json` (owned by `hermes`,
mode `0600`, outside the Docker mount, Git, and the Nix store) is rewritten only
when a request is claimed. Binding enables all three routines;
`hermes-prayer-refresh` then reconciles the dated slots after the bind, on every
gateway start, and weekly from its own systemd timer. No native weekly cron job
is created, so nothing has to be registered by hand.

Turn a routine off from Hermes itself: pausing its dated jobs is a normal cron
pause and the refresh never resumes a paused slot, so the choice survives
rebuilds and reconciles. Re-activating a previously paused slot is explicit.

The same refresh publishes the verified week to
`/var/lib/hermes-organizer/data/prayer-timetable.json`, which the Docker
terminal reads as `/organizer/prayer-timetable.json`. The host writes it whole,
marks it `0444`, and never reads it back, so a terminal-side edit cannot
influence a later refresh. It is published even when every routine is off, and
the routine prompts point at it as read-only reference data. It carries the
`covers` date range it is good for and its own `refreshed_at` stamp, so a
briefing reports prayer data that is missing or out of range instead of
inventing times.

Inspect the resolved state:

```sh
sudo -u hermes hermes-secretary-bind --dry-run   # report the request that would bind
sudo -u hermes hermes-prayer-schedule            # dry-run this week's slots, no writes
sudo -u hermes cat /var/lib/hermes-organizer/data/prayer-timetable.json
sudo -u hermes hermes cron list --all
systemctl status hermes-secretary-bind.timer hermes-prayer-refresh.timer
```

## One-time private seed import

Keep the three `seed/*.yaml` files from the handoff outside Git and the Nix
store. After deployment, copy them to a private directory in the guest using
the existing SSH jump through `home`. The guest's `hermes` user must be able to
read the files. Then run once in the guest:

```sh
sudo -u hermes organizer import-seeds /private/seed/preferences.yaml /private/seed/portfolio.yaml /private/seed/topic-registry.yaml
sudo -u hermes organizer status
```

`import-seeds` refuses a nonempty store and records a migration marker. A
repeat import is a no-op. A Nix rebuild never reads or overwrites seed data.
The gateway uses `/var/lib/hermes-organizer/data`; its Docker terminal sees
the same directory at `/organizer` and can run
`python3 /opt/hermes-organizer/organizer.py`. This writable mount helps with
ordinary local records; it is not an approval boundary. No topic identity is
bound and no reminder is activated on import.

Seeding is a one-time owner action and stays out of the deployment path, so a
machine rebuilt from this repository legitimately starts with zero projects.
Nothing in the configuration reads or restores a seed bundle.

## Owner checklist

1. Add `GROQ_API_KEY` to the existing encrypted `hermes-env` credential flow.
   Keep it out of the repository and terminal forwarding. Test a short voice
   message after the VM starts; replies remain text.
2. Confirm the existing `openai-codex` subscription login still works in the
   guest. Do not choose a Sol ID until the account's available model catalog is
   checked. Automatic Sol consultation is unavailable in this stage.
3. Authorize the personal Google account through a reviewed, scoped
   integration when one is implemented. Record the private planning calendar
   ID outside model-writable data. No Google reads or writes are configured yet.
4. In BotFather, confirm the current bot supports DM topics. Create or identify
   Desk, General, and System in Telegram. Binding requires authenticated
   bot/chat/thread metadata; labels or numbers in chat text are insufficient.
   The topic adapter and Desk delivery ledger are not enabled in this stage.
5. Verify the actual Friday mosque arrangement. The host-side `schedule.py`
   now fetches dated WLY01 data from the official JAKIM e-Solat duration API.
   It validates the seven dates, zone, status, prayer ordering, and fetch time.
   The dry-run command is `hermes-prayer-schedule`.
   It computes one-shot native cron slots for Fajr +60 minutes and Asr +30
   minutes in Asia/Kuala_Lumpur. When the coming week's variation is at most
   two minutes, it uses the same early approximate time for that routine;
   otherwise it keeps each day's calculated time. Friday's review replaces
   its check-in. The verified week is also published for the agent at
   `/organizer/prayer-timetable.json`, so a briefing quotes the same data the
   schedule was built from.
6. Bind Desk by running `/desk-setup` in the target topic after the gateway is
   up (plain `desk setup` also works). `hermes-secretary-bind` claims it within
   a minute, reads the chat and thread from the gateway's session record,
   enables the three routines, and triggers the reconcile. The request is
   recorded, so the binding survives restarts and a stale request cannot
   re-point delivery. Each dated slot has a stable name, so a refresh updates it
   through the pinned Hermes job API or creates it once. Routine deliveries opt
   in to reply continuity for the bound Desk topic. The pinned cron engine
   retires one-shot jobs more than two minutes late, avoiding stale bursts.
   Building this repository alone creates no job, binds nothing, and activates
   no routine.
7. Live-check a one-off reminder and its Desk delivery, plus cron list/edit/
   pause/remove, restart behavior, Friday replacement, and webhook isolation
   after deployment. The current repository build cannot perform those VM
   delivery checks. Note that the binding lives in guest state, so a machine
   rebuilt without restored state needs one `/setup-desk` again; that is the
   only interactive step on the Hermes side. Backup/restore of the VM state
   disk, Google approval handling, topic routing beyond the bound Desk target,
   and optional Sol consultation still need separate implementation or review.
