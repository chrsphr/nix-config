{ config, pkgs, lib, ... }:

{
  # Open firewall ports
  networking.firewall = {
    allowedTCPPorts = [ 22 53 80 ];
    allowedUDPPorts = [ 53 ];
  };


  services.pihole-ftl = {
    enable = true;
    openFirewallDHCP = true;
    
    queryLogDeleter.enable = true;
    lists = [
      {
        url = "https://raw.githubusercontent.com/StevenBlack/hosts/master/hosts";
        type = "block";
        enabled = true;
        description = "Steven Black's unified adlist";
      }
    ];
    settings = {
      dns = {
        domainNeeded = true;
        expandHosts = true;
        interface = "eth0";
        listeningMode = "BIND";
        upstreams = [
            "208.67.222.222"
            "208.67.220.220"
            "2620:119:35::35"
            "2620:119:53::53"
        ];
      };
      dhcp = {
        active = false;

      };
      webserver.api = {
        pwhash = "$BALLOON-SHA256$v=1$s=1024,t=32$0ryHODlDWJn1L0uBamA2Zg==$zq/YS/1/qOqhbXbcoKGf7hdWWVv3Tqd0Dn7iVwYKAf4=";
      };
    };
  };


    services.pihole-web = {
        enable = true;
        ports = [ 80 ];
    };

  # Update gravity database on boot and daily
  systemd.services.pihole-gravity-update = {
    description = "Update Pi-hole gravity database";
    after = [ "pihole-ftl.service" "network-online.target" ];
    wants = [ "network-online.target" ];
    serviceConfig = {
      Type = "oneshot";
      ExecStart = "${pkgs.bash}/bin/bash -c '/run/current-system/sw/bin/pihole -g'";
    };
  };

  # Trigger gravity update whenever pihole-ftl (re)starts
  systemd.services.pihole-ftl.serviceConfig.ExecStartPost =
    "+${pkgs.systemd}/bin/systemctl --no-block start pihole-gravity-update.service";

  systemd.timers.pihole-gravity-update = {
    wantedBy = [ "timers.target" ];
    timerConfig = {
      OnBootSec = "10min";
      OnUnitActiveSec = "24h";
    };
  };




  ### Packages
  environment.systemPackages = with pkgs; [
    dig
  ];




}
