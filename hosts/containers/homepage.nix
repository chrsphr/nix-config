{ config, pkgs, pkgs-unstable, lib, ... }:

# Homepage homelab dashboard as a NixOS container on minihutch.
# Runs Homepage v2 from pkgs-unstable with Glances node metrics and service widgets.

let
  hostsLib = import ../../lib/network.nix { inherit lib; };
  hutchIP = hostsLib.getIP "hutch";
  minihutchIP = hostsLib.getIP "minihutch";
in
{
  imports = [
    ./common.nix
  ];

  networking = {
    hostName = "homepage";
    firewall.allowedTCPPorts = [ 8082 ];
  };

  services.homepage-dashboard = {
    enable = true;
    package = pkgs-unstable.homepage-dashboard;
    listenPort = 8082;
    openFirewall = true;
    allowedHosts = "localhost:8082,127.0.0.1:8082,${hostsLib.getIP "homepage"}:8082,homepage.${hostsLib.domain},home.${hostsLib.domain}";

    settings = {
      title = "Hutch Fleet";
      theme = "dark";
      color = "slate";
      statusStyle = "dot";
      layout = {
        Infrastructure = {
          style = "row";
          columns = 2;
        };
        Media = {
          style = "row";
          columns = 4;
        };
        "Network & Core" = {
          style = "row";
          columns = 3;
        };
      };
    };

    widgets = [
      {
        glances = {
          url = "http://${hutchIP}:61208";
          version = 4;
          label = "hutch (NAS)";
          cpu = true;
          mem = true;
          disk = "/";
          uptime = true;
        };
      }
      {
        glances = {
          url = "http://${minihutchIP}:61208";
          version = 4;
          label = "minihutch (compute)";
          cpu = true;
          mem = true;
          disk = "/";
          uptime = true;
        };
      }
    ];

    services = [
      {
        Media = [
          {
            Plex = {
              icon = "plex.png";
              href = "https://plex.${hostsLib.domain}";
              description = "Media Server";
              siteMonitor = "http://${hostsLib.getIP "plex"}:32400/identity";
            };
          }
          {
            Sonarr = {
              icon = "sonarr.png";
              href = "https://sonarr.${hostsLib.domain}";
              description = "TV Automation";
              siteMonitor = "http://${hostsLib.getIP "sonarr"}:8989/ping";
            };
          }
          {
            Transmission = {
              icon = "transmission.png";
              href = "https://transmission.${hostsLib.domain}";
              description = "BitTorrent Client";
              widget = {
                type = "transmission";
                url = "http://${hostsLib.getIP "transmission"}:9091";
                rpcUrl = "/transmission/rpc";
              };
            };
          }
          {
            Immich = {
              icon = "immich.png";
              href = "https://immich.${hostsLib.domain}";
              description = "Photos & Videos";
              siteMonitor = "http://${hostsLib.getIP "immich"}:2283/api/server/ping";
            };
          }
        ];
      }
      {
        "Network & Core" = [
          {
            "Pi-hole Primary" = {
              icon = "pi-hole.png";
              href = "https://pihole-1.${hostsLib.domain}/admin";
              description = "DNS 1 (hutch)";
              ping = hostsLib.getIP "pihole-1";
            };
          }
          {
            "Pi-hole Secondary" = {
              icon = "pi-hole.png";
              href = "https://pihole-2.${hostsLib.domain}/admin";
              description = "DNS 2 (minihutch)";
              ping = hostsLib.getIP "pihole-2";
            };
          }
          {
            Uptime = {
              icon = "gatus.png";
              href = "https://uptime.${hostsLib.domain}";
              description = "Gatus Status";
              widget = {
                type = "gatus";
                url = "http://${hostsLib.getIP "uptime"}:3001";
              };
            };
          }
        ];
      }
      {
        Infrastructure = [
          {
            "Home Assistant" = {
              icon = "home-assistant.png";
              href = "https://ha.${hostsLib.domain}";
              description = "Home Automation";
              siteMonitor = "http://${hostsLib.getIP "ha"}:8123";
            };
          }
          {
            "Grid Ingester" = {
              icon = "postgres.png";
              href = "https://grid.${hostsLib.domain}";
              description = "GB Power Grid & BMRS";
              siteMonitor = "http://${hostsLib.getIP "gb-grid"}:3000";
            };
          }
        ];
      }
    ];
  };
}
