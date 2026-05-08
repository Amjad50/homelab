{ ... }:
{
  imports = [
    ./fail2ban.nix
    ./networking.nix
    ./services/index.nix
  ];

  homelab.machineName = "middle";

  # Sops global config using SSH host keys
  sops = {
    defaultSopsFile = ./secrets.yaml;
    defaultSopsFormat = "yaml";
    age.sshKeyPaths = [ "/etc/ssh/ssh_host_ed25519_key" ];
  };
}
