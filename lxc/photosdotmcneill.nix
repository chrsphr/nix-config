{ config, pkgs, lib, ... }:

let
  hostsLib = import ../hosts.nix { inherit lib; };
in
{
  imports = [
    ./common-lxc.nix
    ../modules/cloudflare-tunnel.nix
  ];

  networking = hostsLib.mkStaticNetwork "photosdotmcneill" // {
    hostName = "photosdotmcneill";
    firewall.allowedTCPPorts = [ 80 ];
  };

  sops = {
    defaultSopsFile = ../secrets/photosdotmcneill.yaml;
    age.sshKeyPaths = [ "/etc/ssh/ssh_host_ed25519_key" ];
    secrets.cloudflare_tunnel_token = {};
  };


  services.caddy = {
    enable = true;
    virtualHosts.":80" = {
      extraConfig = ''
        root * /var/www/photos
        file_server
        encode gzip

        @static path *.jpg *.jpeg *.png *.gif *.webp *.ico *.css *.js *.woff *.woff2
        header @static Cache-Control "public, max-age=2592000, immutable"
      '';
    };
  };

  services.cloudflare-tunnel = {
    enable = true;
    tokenFile = config.sops.secrets.cloudflare_tunnel_token.path;
  };
}
