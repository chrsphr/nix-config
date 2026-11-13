{ config, pkgs, pkgs-unstable, lib, network, ... }:

# Homepage homelab dashboard as a NixOS container on minihutch.
# Runs Homepage v2 from pkgs-unstable with Glances node metrics and service widgets.

let
  hutchIP = network.getIP "hutch";
  minihutchIP = network.getIP "minihutch";
  port = network.hosts.homepage.port;
  p = toString port;
  # http://<address>:<port from lib/network.nix><path> for a host.
  serviceUrl = name: path:
    "http://${network.getIP name}:${toString network.hosts.${name}.port}${path}";
in
{
  services.homepage-dashboard = {
    enable = true;
    package = pkgs-unstable.homepage-dashboard;
    listenPort = port;
    openFirewall = true;
    allowedHosts = "localhost:${p},127.0.0.1:${p},${network.getIP "homepage"}:${p},homepage.${network.domain},home.${network.domain}";

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
          columns = 4;
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
              href = "https://plex.${network.domain}";
              description = "Media Server";
              siteMonitor = serviceUrl "plex" "/identity";
            };
          }
          {
            Sonarr = {
              icon = "sonarr.png";
              href = "https://sonarr.${network.domain}";
              description = "TV Automation";
              siteMonitor = serviceUrl "sonarr" "/ping";
            };
          }
          {
            Radarr = {
              icon = "radarr.png";
              href = "https://radarr.${network.domain}";
              description = "Movie Automation";
              siteMonitor = serviceUrl "radarr" "/ping";
            };
          }
          {
            Transmission = {
              icon = "transmission.png";
              href = "https://transmission.${network.domain}";
              description = "BitTorrent Client";
              widget = {
                type = "transmission";
                url = serviceUrl "transmission" "";
                rpcUrl = "/transmission/rpc";
              };
            };
          }
          {
            Immich = {
              icon = "immich.png";
              href = "https://immich.${network.domain}";
              description = "Photos & Videos";
              siteMonitor = serviceUrl "immich" "/api/server/ping";
            };
          }
        ];
      }
      {
        "Network & Core" = [
          {
            "Pi-hole Primary" = {
              icon = "pi-hole.png";
              href = "https://pihole-1.${network.domain}/admin";
              description = "DNS 1 (hutch)";
              ping = network.getIP "pihole-1";
            };
          }
          {
            "Pi-hole Secondary" = {
              icon = "pi-hole.png";
              href = "https://pihole-2.${network.domain}/admin";
              description = "DNS 2 (minihutch)";
              ping = network.getIP "pihole-2";
            };
          }
          {
            Uptime = {
              icon = "gatus.png";
              href = "https://uptime.${network.domain}";
              description = "Gatus Status";
              widget = {
                type = "gatus";
                url = serviceUrl "uptime" "";
              };
            };
          }
          {
            Prometheus = {
              icon = "prometheus.png";
              href = "https://prometheus.${network.domain}";
              description = "Metrics & Alerts";
              widget = {
                type = "prometheus";
                url = serviceUrl "prometheus" "";
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
              href = "https://ha.${network.domain}";
              description = "Home Automation";
              siteMonitor = serviceUrl "ha" "";
            };
          }
          {
            "Grid Ingester" = {
              icon = "postgres.png";
              href = "https://grid.${network.domain}";
              description = "GB Power Grid & BMRS";
              siteMonitor = serviceUrl "gb-grid" "";
            };
          }
        ];
      }
    ];
  };
}
