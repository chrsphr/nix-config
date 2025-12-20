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

  # Pi-hole FTL service (DNS only, web served by lighttpd)
  services.pihole-ftl = {
    enable = true;
    
    # Don't auto-open firewall, we'll do it manually above
    openFirewallDNS = false;
    openFirewallWebserver = false;
    
    # Settings
    settings = {
      # Disable built-in webserver, use lighttpd instead
      webserver = {
        port = 0;  # Disable
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
    pihole-web
    php
  ];

  # Lighttpd web server for Pi-hole web interface
  services.lighttpd = {
    enable = true;
    document-root = "${pkgs.pihole-web}/share";
    port = 80;
    enableModules = [ "mod_alias" "mod_fastcgi" ];
    extraConfig = ''
      server.indexfiles = ( "index.lp", "index.php", "index.html" )
      alias.url += (
        "/admin" => "${pkgs.pihole-web}/share"
      )
      fastcgi.server = (
        ".php" => (
          "php" => (
            "socket" => "/run/php-fpm/pihole.sock",
            "broken-scriptfilename" => "enable"
          )
        )
      )
    '';
  };

  # PHP-FPM for running PHP
  services.phpfpm.pools.pihole = {
    user = "lighttpd";
    settings = {
      "listen" = "/run/php-fpm/pihole.sock";
      "pm" = "dynamic";
      "pm.max_children" = 5;
    };
  };
}