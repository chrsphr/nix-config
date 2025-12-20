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
  #networking.firewall.allowedTCPPorts = [ 22 80 53 443];
  #networking.firewall.allowedUDPPorts = [ 53 ];

  ### Pi-hole DNS only
  services.pihole-ftl = {
    enable = true;
    openFirewallDNS = true;
    openFirewallWebserver = true;

    settings = {
      dns.upstreams = [ "1.1.1.1" "1.0.0.1" ];
    };
  };

  services.pihole-web = {
  enable = true;
};


  ### Packages
  environment.systemPackages = with pkgs; [
    dig
  ];




}
