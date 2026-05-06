# Single source of truth for all hosts
# Used to generate static IPs, Caddy config, firewall rules, etc.
{ lib }:

let
  # Network defaults
  gateway = "192.168.1.1";
  nameservers = [ "192.168.1.9" "192.168.1.10" ];
  domain = "mcneill.fyi";

  # Host definitions
  hosts = {
    pihole-1 = {
      ip = "192.168.1.9";
      port = 80;
      caddy = true;
    };
    pihole-2 = {
      ip = "192.168.1.10";
      port = 80;
      caddy = true;
    };
    immich = {
      ip = "192.168.1.127";
      port = 2283;
      caddy = true;
    };
    caddy = {
      ip = "192.168.1.239";
    };
    tailscale = {
      ip = "192.168.1.207";
    };
    plex = {
      ip = "192.168.1.209";
      port = 32400;
      caddy = true;
    };
    transcode = {
      ip = "192.168.1.74";
    };
    photosdotmcneill = {
      ip = "192.168.1.240";
    };
    grafana = {
      ip = "192.168.1.122";
      port = 3000;
      caddy = true;
    };
    sonarr = {
      ip = "192.168.1.75";
      port = 8989;
      caddy = true;
    };
    transmission = {
      ip = "192.168.1.136";
      port = 9091;
      caddy = true;
    };
    uptime-kuma = {
      ip = "192.168.1.31";
      port = 3001;
      caddy = true;
      subdomain = "uptime";
    };
    paperless = {
      ip = "192.168.1.32";
      port = 28981;
      caddy = true;
      subdomain = "paper";
    };
    claude-agent = {
      ip = "192.168.1.33";
    };
    mealie = {
      ip = "192.168.1.34";
      port = 9000;
      caddy = true;
      subdomain = "food";
    };
    desktop = {
      ip = "192.168.1.181";
    };
    gb-grid = {
      ip = "192.168.1.28";
    };

    # Non-NixOS hosts (for Caddy config generation)
    ha = {
      ip = "192.168.1.11";
      port = 8123;
      caddy = true;
      subdomain = "ha";
      headers = true;
    };
    lilnas = {
      ip = "192.168.1.12";
      port = 443;
      caddy = true;
      https = true;
    };
  };

  # Filter hosts that should be in Caddy
  caddyHosts = lib.filterAttrs (name: cfg: cfg.caddy or false) hosts;

  # Generate a single Caddy host block
  mkHostBlock = name: cfg:
    let
      subdomain = cfg.subdomain or name;
      backend = if cfg.https or false
        then "https://${cfg.ip}:${toString cfg.port}"
        else "${cfg.ip}:${toString cfg.port}";
      tlsConfig = lib.optionalString (cfg.https or false) ''
        transport http {
          tls_insecure_skip_verify
        }
      '';
      headersConfig = lib.optionalString (cfg.headers or false) ''
        header_up X-Forwarded-For {remote_host}
        header_up X-Forwarded-Proto {scheme}
        header_up X-Forwarded-Host {host}
      '';
      hasInnerConfig = (cfg.https or false) || (cfg.headers or false);
      innerBlock = if hasInnerConfig then '' {
${headersConfig}${tlsConfig}      }'' else "";
    in ''
        @${lib.strings.sanitizeDerivationName name} host ${subdomain}.${domain}
        handle @${lib.strings.sanitizeDerivationName name} {
          reverse_proxy ${backend}${innerBlock}
        }
    '';

in {
  inherit gateway nameservers domain hosts;

  # Generate static network config for a host
  mkStaticNetwork = hostname: {
    useDHCP = false;
    interfaces.eth0.ipv4.addresses = [{
      address = hosts.${hostname}.ip;
      prefixLength = 24;
    }];
    defaultGateway = {
      address = gateway;
      interface = "eth0";
    };
    inherit nameservers;
  };

  # Get IP for a host
  getIP = hostname: hosts.${hostname}.ip;

  # Get port for a host
  getPort = hostname: hosts.${hostname}.port or null;

  # Generate full Caddy extraConfig
  generateCaddyConfig = lib.concatStringsSep "\n" (lib.mapAttrsToList mkHostBlock caddyHosts);
}
