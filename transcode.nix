{ config, pkgs, lib, ... }:

{
  imports = [
    ./common.nix
  ];
  
  networking.hostName = "transcode";

  environment.systemPackages = with pkgs; [
  ffmpeg-full
];



}