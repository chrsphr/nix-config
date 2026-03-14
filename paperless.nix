{ config, pkgs, pkgs-unstable, lib, ... }:

let
  hostsLib = import ./hosts.nix { inherit lib; };
in
{
  imports = [
    ./common.nix
  ];

  networking = hostsLib.mkStaticNetwork "paperless" // {
    hostName = "paperless";
    firewall.allowedTCPPorts = [ 28981 ];
  };

  # SOPS secrets
  sops = {
    defaultSopsFile = ./secrets/paperless.yaml;
    age.sshKeyPaths = [ "/etc/ssh/ssh_host_ed25519_key" ];
    secrets.paperless_secret_key = {
      owner = "paperless";
    };
  };

  services.paperless = {
    enable = true;
    package = pkgs-unstable.paperless-ngx;
    address = "0.0.0.0";
    port = 28981;
    mediaDir = "/mnt/media/Documents";
    settings = {
      PAPERLESS_OCR_LANGUAGE = "eng";
      PAPERLESS_TIME_ZONE = "Europe/London";
      PAPERLESS_ADMIN_USER = "admin";
      PAPERLESS_SECRET_KEY_FILE = config.sops.secrets.paperless_secret_key.path;
      PAPERLESS_URL = "https://paper.mcneill.fyi";
      PAPERLESS_CSRF_TRUSTED_ORIGINS = "https://paper.mcneill.fyi,http://192.168.1.32:28981";
    };
  };
}
