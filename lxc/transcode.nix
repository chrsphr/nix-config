{ config, pkgs, lib, ... }:

{
  imports = [
    ./common-lxc.nix
  ];
  
  networking.hostName = "transcode";

  environment.systemPackages = with pkgs; [
  ffmpeg-full
];



}