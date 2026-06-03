# chezmoi dotfile management
#
# User-level dotfiles (zsh, git, nvim, p10k) are managed by chezmoi from
# https://github.com/Amjad50/dotfiles rather than home-manager. This module
# installs chezmoi and runs a per-user systemd service that initialises and
# applies the dotfiles on boot.
#
# Servers are registered in the dotfiles repo's .chezmoidata/packages.yaml with
# `tags: []`, so they receive only dotfiles — none of the personal-only scripts
# (syncthing/notes/fonts) run, and no age-encrypted files are decrypted, so no
# age key is required on servers.
{
  config,
  lib,
  pkgs,
  ...
}:

let
  # Public HTTPS clone URL — no SSH key or token needed on servers.
  dotfilesRepo = "https://github.com/Amjad50/dotfiles.git";
  user = "amjad";

  # init-or-apply: clone+apply on first run, plain apply (which pulls) after.
  # Logs to the journal; never fails the boot.
  chezmoiScript = pkgs.writeShellScript "chezmoi-apply" ''
    set -u
    export PATH=${
      lib.makeBinPath [
        pkgs.chezmoi
        pkgs.git
        pkgs.openssh
        # chezmoi runs run_onchange_*.sh scripts (shebang: /usr/bin/env bash);
        # bash must be on PATH for `env bash` to resolve.
        pkgs.bash
      ]
    }:$PATH

    sourceDir="$HOME/.local/share/chezmoi"

    if [ -d "$sourceDir/.git" ]; then
      echo "chezmoi already initialised, applying latest..."
      chezmoi update --apply --force
    else
      echo "chezmoi not initialised, cloning ${dotfilesRepo} and applying..."
      chezmoi init --apply --force ${dotfilesRepo}
    fi
  '';
in
{
  environment.systemPackages = [ pkgs.chezmoi ];

  systemd.user.services.chezmoi-apply = {
    description = "Apply chezmoi-managed dotfiles";
    # Only run for the amjad user, not e.g. the dock service user.
    unitConfig.ConditionUser = user;
    after = [ "network-online.target" ];
    wants = [ "network-online.target" ];
    wantedBy = [ "default.target" ];
    serviceConfig = {
      Type = "oneshot";
      ExecStart = "${chezmoiScript}";
      # Don't let a failed apply mark the user session degraded / block login.
      SuccessExitStatus = "0 1";
    };
  };
}
