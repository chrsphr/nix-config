{ config, pkgs, lib, ... }:

{
  options.services.cloudflare-tunnel = {
    enable = lib.mkEnableOption "Cloudflare Tunnel";

    tokenFile = lib.mkOption {
      type = lib.types.path;
      description = "Path to file containing the Cloudflare tunnel token";
    };
  };

  config = lib.mkIf config.services.cloudflare-tunnel.enable {
    environment.systemPackages = [ pkgs.cloudflared ];

    systemd.services.cloudflared-tunnel = {
      description = "Cloudflare Tunnel";
      after = [ "network-online.target" ];
      wants = [ "network-online.target" ];
      wantedBy = [ "multi-user.target" ];
      script = ''
        ${pkgs.cloudflared}/bin/cloudflared tunnel --no-autoupdate run --token "$(cat ${config.services.cloudflare-tunnel.tokenFile})"
      '';
      serviceConfig = {
        Restart = "on-failure";
        RestartSec = "5s";
      };
    };
  };
}
