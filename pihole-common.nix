{ config, pkgs, lib, ... }:

{
  imports = [
    ./common.nix
  ];

  # Static IP configuration (override hostname and address in specific configs)
  networking = {
    useDHCP = false;
    interfaces.eth0.ipv4.addresses = lib.mkDefault [{
      address = "192.168.1.9";  # Override this
      prefixLength = 24;
    }];
    defaultGateway = "192.168.1.1";
    nameservers = [ "1.1.1.1" ];
  };

  # Open ports for Pi-hole
  networking.firewall = {
    allowedTCPPorts = [ 
      22    # SSH
      80    # HTTP Web Interface
      53    # DNS
    ];
    allowedUDPPorts = [ 
      53    # DNS
    ];
  };

  # Pi-hole FTL service
  services.pihole-ftl = {
    enable = true;
    
    # Web interface settings
    webserver = {
      enable = true;
      port = 80;
    };
    
    # DNS settings
    dns = {
      upstreams = [
        "1.1.1.1"
        "1.0.0.1"
      ];
    };
  };

  # Additional packages useful for Pi-hole management
  environment.systemPackages = with pkgs; [
    dig
  ];
}