{ config, pkgs, sops-nix, lib, ... }:

# Outbound-only Cloudflare Tunnel sidecar on VLAN 5. It forwards
# share.mcneill.fyi to Gokapi at gokapi.internal:53842 without opening an
# inbound port; Gokapi keeps privateUsers because this container owns the
# sops token instead.

{
  imports = [
    ./common.nix
    ../../modules/cloudflare-tunnel.nix
    sops-nix.nixosModules.sops
  ];

  networking.hostName = "cloudflared";

  sops = {
    defaultSopsFile = ../../secrets/cloudflared.yaml;
    age.keyFile = "/var/secrets/keys.txt";
    secrets.cloudflare_tunnel_token = {
      # Persistent path, not /run/secrets. why: docs/notes.md#secrets-under-var
      path = "/var/lib/sops/cloudflare_tunnel_token";
    };
  };

  services.cloudflare-tunnel = {
    enable = true;
    tokenFile = config.sops.secrets.cloudflare_tunnel_token.path;
  };
}
