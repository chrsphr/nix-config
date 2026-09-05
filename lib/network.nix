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
  #   ip, port, caddy, subdomain, https — used by Caddy generation
  #   headers  = bool    forward X-Real-IP (Caddy already sets X-Forwarded-For/
  #                      Proto/Host by default; immich's docs explicitly also
  #                      want X-Real-IP)
  #   maxBody  = string  request body limit (e.g. "50GB")
  #   timeouts = string  upstream read/write timeout (e.g. "600s")
  #   redirect = string  redirect "/" here before proxying (e.g. "/transmission/web/")
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
      # NixOS container on the named parent — every host with a `parent` gets
      # one, declared by that parent via modules/container-host.nix.
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
      parent = "minihutch";
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
      parent = "hutch";
      port = 2283;
      caddy = true;
      headers = true;
      maxBody = "50GB";
      timeouts = "600s";
      monitor = {
        type = "http"; name = "Immich"; path = "/api/server/ping";
        group = "Hutch Primary Services";
      };
    };
    caddy = {
      ip = "192.168.1.239";
      sshUser = "deploy";
      parent = "minihutch";
      monitor = {
        type = "http"; name = "caddy"; url = "https://caddy.${domain}";
        group = "Hutch Primary Services";
      };
    };
    tailscale = {
      ip = "192.168.1.207";
      sshUser = "deploy";
      parent = "minihutch";
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
    # Co-located with sonarr in the same container, so no `parent` (and no
    # container) of its own.
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
      redirect = "/transmission/web/";
      monitor = {
        type = "http"; name = "Transmission"; path = "/transmission/web/";
      };
    };
    uptime = {
      ip = "192.168.1.31";
      sshUser = "deploy";
      parent = "minihutch";
      port = 3001;
      caddy = true;
    };
    network-optimizer = {
      ip = "192.168.1.84";
      sshUser = "deploy";
      parent = "hutch";
      port = 8042;
      caddy = true;
      subdomain = "optm";
      monitor = {
        type = "http"; name = "Network Optimizer"; path = "/api/health";
        group = "Hutch Primary Services";
      };
    };

    beeper = {
      ip = "192.168.1.40";
      sshUser = "deploy";
      parent = "minihutch";
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

    # The two baremetal container hosts (see README). Probed on sshd:22, not a
    # service port. why: docs/notes.md#deploy-ordering-and-sshd-probe
    hutch = {
      ip = "192.168.1.2";
      sshUser = "deploy";
      monitor = {
        type = "port"; targetPort = 22; name = "hutch (NAS + containers)";
        group = "Servers";
      };
    };
    minihutch = {
      ip = "192.168.1.3";
      sshUser = "deploy";
      monitor = {
        type = "port"; targetPort = 22; name = "minihutch (containers)";
        group = "Servers";
      };
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

      # Lines emitted inside the reverse_proxy block. Caddy already forwards
      # X-Forwarded-For/Proto/Host by default, so `headers` only adds
      # X-Real-IP (which Caddy does not set on its own).
      transportLines =
        lib.optional (cfg.https or false) "tls_insecure_skip_verify"
        ++ lib.optionals (cfg ? timeouts) [
          "read_timeout ${cfg.timeouts}"
          "write_timeout ${cfg.timeouts}"
        ];
      proxyLines =
        lib.optional (cfg.headers or false) "header_up X-Real-IP {remote_host}"
        ++ lib.optionals (transportLines != [])
          ([ "transport http {" ] ++ map (line: "  ${line}") transportLines ++ [ "}" ]);
      proxyBlock = lib.optionalString (proxyLines != [])
        (" {\n"
          + lib.concatMapStringsSep "\n" (line: "    ${line}") proxyLines
          + "\n  }");
    in lib.concatStringsSep "\n"
      ([
        "@${lib.strings.sanitizeDerivationName name} host ${subdomain}.${domain}"
        "handle @${lib.strings.sanitizeDerivationName name} {"
      ]
      ++ lib.optional (cfg ? redirect) "    redir / ${cfg.redirect} 302"
      # request_body is a top-level directive, NOT a reverse_proxy
      # sub-directive — it must be a sibling, not nested inside it.
      ++ lib.optional (cfg ? maxBody) "    request_body { max_size ${cfg.maxBody} }"
      ++ [ "    reverse_proxy ${backend}${proxyBlock}" "}" ]);

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

  # Get IP for a host
  getIP = hostname: hosts.${hostname}.ip;

  # Generate full Caddy extraConfig
  generateCaddyConfig = lib.concatStringsSep "\n" (lib.mapAttrsToList mkHostBlock caddyHosts);

  # Generate Gatus endpoints list from hosts.nix monitor metadata.
  #   defaultAlerts: list applied to monitors that don't set their own
  #   extra:         additional endpoints not tied to any host (e.g. external probes)
  generateGatusEndpoints = { defaultAlerts ? [], extra ? [] }:
    lib.flatten (lib.mapAttrsToList (mkHostEndpoints defaultAlerts) hosts) ++ extra;
}
