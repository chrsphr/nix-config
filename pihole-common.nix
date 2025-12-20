{ config, pkgs, lib, ... }:

{
  # Static IP configuration (override in specific configs)
  networking = {
    useDHCP = false;
    interfaces.eth0.ipv4.addresses = lib.mkDefault [{
      address = "192.168.1.9";  # Override this
      prefixLength = 24;
    }];
    defaultGateway = {
      address = "192.168.1.1";
      interface = "eth0";
    };
    nameservers = [ "1.1.1.1" ];
  };

  # Pi-hole FTL service
  services.pihole-ftl = {
    enable = true;
    
    # Open firewall ports
    openFirewallDNS = true;
    openFirewallWebserver = true;
    
    # Settings go in the settings attribute
    settings = {
      webserver = {
        port = 80;
      };
      
      dns = {
        upstreams = [
          "1.1.1.1"
          "1.0.0.1"
        ];
      };
    };
  };

  # Additional packages useful for Pi-hole management
  environment.systemPackages = with pkgs; [
    dig
  ];
}