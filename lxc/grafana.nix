{ config, pkgs, lib, ... }:

let
  hostsLib = import ../hosts.nix { inherit lib; };
in
{
  imports = [
    ./common-lxc.nix
  ];

  networking = hostsLib.mkStaticNetwork "grafana" // {
    hostName = "grafana";
    firewall.allowedTCPPorts = [ 3000 ];
  };

  services.grafana = {
    enable = true;
    settings = {
      server = {
        http_addr = "0.0.0.0";
        http_port = 3000;
      };
    };
  };
}
