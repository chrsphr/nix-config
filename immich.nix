{ config, pkgs, lib, ... }:

{
  imports = [
    ./common.nix
  ];

  ### Networking (adjust IP as needed)
  networking = {
    hostName = "immich";
    #interfaces.eth0.ipv4.addresses = [{
    #  address = "192.168.1.9";
    #  prefixLength = 24;
    #}];
    #defaultGateway = {
    #address = "192.168.1.1";
    #interface = "eth0";
    #};
    #nameservers = [ "1.1.1.1" ];
  };

 
  services.immich = {
    enable = true;
    host = "0.0.0.0";
    port = 2283;
    mediaLocation = "/var/lib/immich";
  };

  #services.postgresql = {
  #  enable = true;
  #  ensureDatabases = [ "immich" ];
  #  ensureUsers = [{
  #    name = "immich";
  #    ensureDBOwnership = true;
  #  }];
  #};

  #services.redis.enable = true;

  environment.systemPackages = with pkgs; [
    ffmpeg
  ];

  networking.firewall.allowedTCPPorts = [ 2283 ];



}