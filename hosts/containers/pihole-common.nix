{ config, pkgs, lib, ... }:

{
  # Open firewall ports and set custom DNS to avoid loops
  networking = {
    firewall = {
      allowedTCPPorts = [ 22 53 80 443];
      allowedUDPPorts = [ 53 ];
    };
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
            "1.1.1.1#53"
            "1.0.0.1#53"
            "2606:4700:4700::1111#53"
            "2606:4700:4700::1001#53"
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

  # ── Disable systemd-resolved (conflicts on port 53) ─────────────────────────
  services.resolved.enable = false;

  # NOT 127.0.0.1 — that deadlocks the boot. why: docs/notes.md#container-one-offs
  networking.nameservers = lib.mkForce [
    "1.1.1.1"
    "1.0.0.1"
    "2606:4700:4700::1111"
    "2606:4700:4700::1001"
  ];



}
