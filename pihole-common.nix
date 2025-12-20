{ config, pkgs, lib, ... }:

{
  ### Networking (adjust IP as needed)
  networking = {
    useDHCP = false;
    interfaces.eth0.ipv4.addresses = [{
      address = "192.168.1.9";
      prefixLength = 24;
    }];
    defaultGateway = {
    address = "192.168.1.1";
    interface = "eth0";
    };
    nameservers = [ "1.1.1.1" ];
  };

  ### Firewall
  networking.firewall.allowedTCPPorts = [ 22 80 53 ];
  networking.firewall.allowedUDPPorts = [ 53 ];

  ### Pi-hole DNS only
  services.pihole-ftl = {
    enable = true;
    openFirewallDNS = false;
    openFirewallWebserver = false;

    settings = {
      webserver.port = 0; # disable embedded server
      dns.upstreams = [ "1.1.1.1" "1.0.0.1" ];
    };
  };

  ### Packages
  environment.systemPackages = with pkgs; [
    dig
    pihole-web
  ];

services.lighttpd = {
  enable = true;
  port = 80;

  document-root = "${pkgs.pihole-web}/share/pihole/web";

  enableModules = [
    "mod_alias"
    "mod_fastcgi"
    "mod_accesslog"
  ];

  extraConfig = ''
    server.indexfiles = ( "index.php", "index.html" )

    alias.url += (
      "/admin/" => "${pkgs.pihole-web}/share/pihole/web/admin/"
    )
  '';
};



}
