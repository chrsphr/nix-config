{ config, pkgs, lib, ... }:

{
  imports = [
    ./common-lxc.nix
  ];
  
  networking.hostName = "transcode";

  environment.systemPackages = with pkgs; [
  ffmpeg-full
  libva-utils  # `vainfo` to verify QSV
];

  # QSV userspace stack so ffmpeg can use -hwaccel qsv/vaapi via the
  # passed-through /dev/dri.
  hardware.graphics = {
    enable = true;
    extraPackages = with pkgs; [ intel-media-driver vpl-gpu-rt ];
  };
}