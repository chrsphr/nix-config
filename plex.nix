{ config, pkgs, lib, ... }:

{
  imports = [
    ./common.nix
  ];
  
  ### Networking (adjust IP as needed)
  networking = {
    hostName = "plex";
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

nixpkgs.config.allowUnfree = true;

services.plex = {
  enable = true;
  openFirewall = true;
  user="plex";
};


}