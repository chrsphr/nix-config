# Single source of truth for all hosts
# Used to generate static IPs, Caddy config, firewall rules, etc.
{ lib }:

let
  # Network defaults
  gateway = "192.168.1.1";
  nameservers = [ "192.168.1.1" ];
  domain = "mcneill.fyi";

  # Host definitions
  #
  # Per-host fields:
  #   ip, port, caddy, subdomain, https, headers — used by Caddy generation
  #   monitor — Gatus monitor spec (attrset or list of attrsets), see below
  #
  # monitor schema (all fields optional unless noted):
  #   type      = "http" | "dns" | "port"             (default "http")
  #   group     = string                              (Gatus group label)
  #   name      = string                              (default host key)
  #   interval  = string                              (default "60s")
  #   alerts    = list                                (else uses generateGatusEndpoints default)
  #
  #   http:
  #     url     = full URL (overrides host ip/port/scheme/path)
  #     scheme  = "http" | "https"  (default "https" if host.https else "http")
  #     path    = "/foo"            (default "/")
  #     insecure= bool              (skip TLS verify, default false)
  #     headers = { Name = "value"; }  (request headers; values may reference
  #                                     ''${ENV_VARS}'' rendered via gatus env file)
  #
  #   dns:
  #     resolver= IP of resolver    (default host.ip)
  #     query   = name to look up   (default "google.com")
  #     family  = "v4" | "v6"       (default "v4"; sets query-type A or AAAA)
  #
  #   port:
  #     targetPort = int            (default host.port)
  hosts = {
    pihole-1 = {
      ip = "192.168.1.9";
      sshUser = "deploy";
      # Proxmox LXC today; container staged on hutch (autoStart = false
      # until cutover — see docs/lxc-migration.md). Same for every host below
      # with `parent = "hutch"`.
      parent = "hutch";
      port = 80;
      caddy = true;
      monitor = [
        { type = "dns"; name = "Pihole 1";        family = "v4"; group = "Hutch Primary Services"; }
        { type = "dns"; name = "Pihole 1 (v6)";   family = "v6"; group = "Hutch Primary Services"; }
      ];
    };
    pihole-2 = {
      ip = "192.168.1.10";
      sshUser = "deploy";
      parent = "hutch";
      port = 80;
      caddy = true;
      monitor = [
        { type = "dns"; name = "Pihole 2";        family = "v4"; group = "Hutch Primary Services"; }
        { type = "dns"; name = "Pihole 2 (v6)";   family = "v6"; group = "Hutch Primary Services"; }
      ];
    };
    immich = {
      ip = "192.168.1.127";
      sshUser = "deploy";
      # Proxmox LXC today; moves to a container on hutch at NAS cutover
      # (autoStart = false in hosts/hutch.nix until then).
      parent = "hutch";
      port = 2283;
      caddy = true;
      monitor = {
        type = "http"; name = "Immich"; path = "/api/server/ping";
        group = "Hutch Primary Services";
      };
    };
    caddy = {
      ip = "192.168.1.239";
      sshUser = "deploy";
      parent = "hutch";
      monitor = {
        type = "http"; name = "caddy"; url = "https://caddy.${domain}";
        group = "Hutch Primary Services";
      };
    };
    tailscale = {
      ip = "192.168.1.207";
      sshUser = "deploy";
      parent = "hutch";
      port = 8080;
      monitor = {
        type = "http"; name = "Tailscale"; path = "/health";
        group = "Hutch Primary Services";
      };
    };
    plex = {
      ip = "192.168.1.209";
      sshUser = "deploy";
      parent = "hutch";
      port = 32400;
      caddy = true;
      monitor = {
        type = "http"; name = "Plex"; path = "/identity";
        group = "Hutch Primary Services";
      };
    };
    sonarr = {
      ip = "192.168.1.75";
      sshUser = "deploy";
      parent = "hutch";
      port = 8989;
      caddy = true;
      monitor = {
        type = "http"; name = "Sonarr API"; path = "/ping";
      };
    };
    # Co-located with sonarr — same LXC today, same container after cutover,
    # so no `parent` (and no container) of its own.
    prowlarr = {
      ip = "192.168.1.75";
      sshUser = "deploy";
      port = 9696;
      caddy = true;
    };
    transmission = {
      ip = "192.168.1.136";
      sshUser = "deploy";
      parent = "hutch";
      port = 9091;
      caddy = true;
      monitor = {
        type = "http"; name = "Transmission"; path = "/transmission/web/";
      };
    };
    uptime = {
      ip = "192.168.1.31";
      sshUser = "deploy";
      parent = "hutch";
      port = 3001;
      caddy = true;
    };

    beeper = {
      ip = "192.168.1.40";
      sshUser = "deploy";
      parent = "hutch";
      monitor = {
        type = "port"; targetPort = 22; name = "Beeper bridges";
        group = "Hutch Primary Services";
      };
    };

    desktop = {
      ip = "192.168.1.181";
      sshUser = "chris";
    };
    gb-grid = {
      ip = "192.168.1.28";
      sshUser = "deploy";
      parent = "hutch";
      port = 3000;
      caddy = true;
      subdomain = "grid";
    };

    # hutch: baremetal server replacing both the TrueNAS VM (NAS role — see
    # modules/nas.nix) and the Proxmox LXCs (services as NixOS containers).
    # Containers (hosts with a `parent` field) are defined on their parent's
    # config; docs/lxc-migration.md + docs/nas-migration.md have the runbooks.
    hutch = {
      ip = "192.168.1.2";
      sshUser = "deploy";
    };

    # Non-NixOS hosts (for Caddy config + monitoring)
    ha = {
      ip = "192.168.1.11";
      sshUser = "root";
      port = 8123;
      caddy = true;
      subdomain = "ha";
      headers = true;
      monitor = {
        type = "http"; name = "Home Assistant"; url = "https://ha.${domain}";
        group = "Hutch Primary Services";
      };
    };
    lilnas = {
      ip = "192.168.1.12";
      sshUser = "root";
      port = 443;
      caddy = true;
      https = true;
      monitor = {
        type = "http"; name = "TrueNAS"; scheme = "https"; insecure = true;
        group = "Hutch Primary Services";
      };
    };
    # Proxmox retired: hutch took over 192.168.1.2. If the box ever comes
    # back at a new IP, re-add its entry here (was: port 8006, https monitor
    # with the PROXMOX_API_TOKEN header — see git history).
    minimox = {
      ip = "192.168.1.30";
      sshUser = "root";
      port = 8006;
      monitor = {
        type = "http"; name = "Minimox"; scheme = "https";
        path = "/api2/json/version"; insecure = true;
        headers.Authorization = "PVEAPIToken=root@pam!uptime2=\${PROXMOX_API_TOKEN}";
        group = "Hutch Primary Services";
      };
    };
    unifi = {
      ip = "192.168.1.1";
      sshUser = "root";
      monitor = [
        { type = "dns"; name = "UniFi DNS";       family = "v4"; }
        { type = "dns"; name = "UniFi DNS (v6)";  family = "v6"; }
      ];
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

  # Build a single Gatus endpoint from a (host, monitor) pair
  mkGatusEndpoint = hostName: hostCfg: m: defaultAlerts:
    let
      type = m.type or "http";
      group = m.group or null;
      name = m.name or hostName;
      interval = m.interval or "60s";
      alerts = m.alerts or defaultAlerts;
      base = {
        inherit name interval;
      } // lib.optionalAttrs (group != null) { inherit group; }
        // lib.optionalAttrs (alerts != []) { inherit alerts; };
    in
      if type == "http" then
        let
          scheme =
            if m ? url then null
            else m.scheme or (if hostCfg.https or false then "https" else "http");
          path = m.path or "/";
          url = m.url or "${scheme}://${hostCfg.ip}:${toString hostCfg.port}${path}";
          insecure = m.insecure or false;
          headers = m.headers or {};
        in base // {
          inherit url;
          conditions = [ "[STATUS] == 200" ];
        } // lib.optionalAttrs insecure { client.insecure = true; }
          // lib.optionalAttrs (headers != {}) { inherit headers; }
      else if type == "dns" then
        let
          resolver = m.resolver or hostCfg.ip;
          family = m.family or "v4";
          queryType = if family == "v6" then "AAAA" else "A";
          query = m.query or "google.com";
        in base // {
          url = resolver;
          dns = { query-name = query; query-type = queryType; };
          conditions = [ "[DNS_RCODE] == NOERROR" ];
        }
      else if type == "port" then
        let
          targetPort = m.targetPort or hostCfg.port;
        in base // {
          url = "tcp://${hostCfg.ip}:${toString targetPort}";
          conditions = [ "[CONNECTED] == true" ];
        }
      else throw "lib/network.nix: unknown monitor type '${type}' for ${hostName}";

  # Expand a host's monitor field (attrset or list) into a list of endpoints
  mkHostEndpoints = defaultAlerts: hostName: hostCfg:
    let
      monitors =
        if !(hostCfg ? monitor) then []
        else if lib.isList hostCfg.monitor then hostCfg.monitor
        else [ hostCfg.monitor ];
    in
      map (m: mkGatusEndpoint hostName hostCfg m defaultAlerts) monitors;

in {
  inherit gateway nameservers domain hosts;

  # Hosts that run as NixOS containers on a given parent host
  getContainers = parent: lib.filterAttrs (name: cfg: (cfg.parent or null) == parent) hosts;

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

  # Generate Gatus endpoints list from hosts.nix monitor metadata.
  #   defaultAlerts: list applied to monitors that don't set their own
  #   extra:         additional endpoints not tied to any host (e.g. external probes)
  generateGatusEndpoints = { defaultAlerts ? [], extra ? [] }:
    lib.flatten (lib.mapAttrsToList (mkHostEndpoints defaultAlerts) hosts) ++ extra;
}
