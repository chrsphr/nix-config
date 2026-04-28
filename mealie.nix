{ config, pkgs, lib, ... }:

let
  hostsLib = import ./hosts.nix { inherit lib; };
in
{
  imports = [
    ./common.nix
  ];

  networking = hostsLib.mkStaticNetwork "mealie" // {
    hostName = "mealie";
    firewall.allowedTCPPorts = [ 9000 ];
  };

  services.mealie = {
    enable = true;
    listenAddress = "0.0.0.0";
    port = 9000;
  };
}
