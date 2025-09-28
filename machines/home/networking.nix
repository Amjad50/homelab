{ ... }:
{

  networking.hostName = "home";

  networking.firewall.allowedTCPPorts = [
    5055
    8096
    8090
  ];

  # Use static ipv4
  networking.interfaces.eno2 = {
    useDHCP = false;
    ipv4.addresses = [
      {
        address = "192.168.0.5";
        prefixLength = 24;
      }
    ];
  };
  networking.defaultGateway = {
    address = "192.168.0.1";
    interface = "eno2";
  };
}
