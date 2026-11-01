{ config, pkgs, pkgs-unstable ? pkgs, lib, ... }:

{
  options.services.cloudflare-tunnel = {
    enable = lib.mkEnableOption "Cloudflare Tunnel";

    tokenFile = lib.mkOption {
      type = lib.types.path;
      description = "Path to file containing the Cloudflare tunnel token";
    };
  };

  config = lib.mkIf config.services.cloudflare-tunnel.enable {
    environment.systemPackages = [ pkgs-unstable.cloudflared ];

    systemd.services.cloudflared-tunnel = {
      description = "Cloudflare Tunnel";
      after = [ "network-online.target" ];
      wants = [ "network-online.target" ];
      wantedBy = [ "multi-user.target" ];
      # --token-file, not --token "$(cat ...)": the latter puts the token in
      # the process command line and journal on every start.
      script = ''
        exec ${pkgs-unstable.cloudflared}/bin/cloudflared tunnel --no-autoupdate run --token-file ${config.services.cloudflare-tunnel.tokenFile}
      '';
      serviceConfig = {
        Restart = "on-failure";
        RestartSec = "5s";
      };
    };
  };
}
