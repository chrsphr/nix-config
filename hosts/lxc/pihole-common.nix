{ config, pkgs, lib, ... }:

{
  # Open firewall ports and set custom DNS to avoid loops
  networking = {
    #nameservers = lib.mkForce [ "1.1.1.1" ];
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
            "127.0.0.1#5335"
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

  services.unbound = {
    enable = true;

    settings = {
      server = {
        # Listen only on loopback — Pi-hole forwards to us
        interface        = [ "127.0.0.1" ];
        port             = 5335;
        do-ip4           = true;
        do-ip6           = true;   # flip to true if you have IPv6
        do-udp           = true;
        do-tcp           = true;

        # Security hardening
        hide-identity    = true;
        hide-version     = true;
        harden-glue      = true;
        harden-dnssec-stripped = true;
        use-caps-for-id  = false;   # QNAME minimisation makes this redundant
        qname-minimisation = true;

        # Performance
        prefetch         = true;
        prefetch-key     = true;
        num-threads      = 2;       # bump to match CPU cores on beefy hardware

        # Cache sizing — unbound's resident footprint runs ~2x the configured
        # caches, and these LXCs only have 2G. A home LAN's hot DNS set fits in
        # a few MB, so keep this small.
        msg-cache-size   = "16m";
        rrset-cache-size = "32m";
        # No cache-min-ttl: forcing a floor serves stale records for CDNs /
        # failover names, and prefetch already keeps popular names warm.
        cache-max-ttl    = 86400;

        # EDNS / upstream buffer
        edns-buffer-size = 1232;

        # Private address ranges — never forward these
        private-address  = [
          "192.168.0.0/16"
          "169.254.0.0/16"
          "172.16.0.0/12"
          "10.0.0.0/8"
          "fd00::/8"
          "fe80::/10"
        ];
      };

      # Root hints — Unbound ships its own, but you can pin a fresh copy:
      # remote-control = { control-enable = false; };
    };
  };

  # Ensure unbound starts before pihole (the unit is pihole-ftl.service —
  # a bare "pihole.service" reference orders against nothing).
  systemd.services.unbound.before = [ "pihole-ftl.service" ];
  systemd.services.pihole-ftl = {
    wants = [ "unbound.service" ];
    after = [ "unbound.service" ];
  };

  # ── Disable systemd-resolved (conflicts on port 53) ─────────────────────────
  services.resolved.enable = false;

  # Point the host itself at Pi-hole
  networking.nameservers = lib.mkForce [ "127.0.0.1" ];
  networking.resolvconf.useLocalResolver = true;



}
