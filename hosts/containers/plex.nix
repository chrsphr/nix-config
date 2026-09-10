{ config, pkgs, pkgs-unstable, lib, ... }:

# Plex as a NixOS container on hutch. The library arrives as read-only binds
# of the local ZFS datasets at /media/{Movies,Music,TV} (see hosts/hutch.nix).

let
  # Custom tvOS client profile: advertises AV1 as direct-play capable so PMS
  # stops transcoding it for the Apple TV (the tvOS app software-decodes it).
  # Content of github.com/currifi/plex_av1_tvos, inlined so it can't drift.
  # why: docs/notes.md#hutch
  tvosProfile = pkgs.writeText "tvOS.xml" ''
    <?xml version="1.0" encoding="utf-8"?>
    <Client name="tvOS">
      <TranscodeTargets>
        <VideoProfile container="mkv" codec="h264,h265,hevc,mpeg2video,mpeg4,vc1,av1" audioCodec="flac" subtitleCodec="ass,dvb_subtitle,vobsub,eia_608,pgs,microdvd,movtext,ssa,srt" />
        <MusicProfile container="flac" codec="flac" />
        <PhotoProfile container="jpeg" />
      </TranscodeTargets>
      <DirectPlayProfiles>
        <VideoProfile container="mkv,mov,mp4,mpegts,mpeg,mpegvideo,avi,flv,ogg" codec="h264,h265,hevc,vp9,h263,mpeg1video,mpeg2video,mpeg4,vc1,av1" audioCodec="aac,ac3,alac,flac,eac3,dca,opus" subtitleCodec="ass,dvb_subtitle,vobsub,eia_608,pgs,microdvd,movtext,ssa,srt" />
        <MusicProfile container="mp3" codec="mp3" />
        <MusicProfile container="m4a" codec="aac,alac" />
        <MusicProfile container="mp4" codec="aac,he-aac,ac3,eac3,alac" />
        <MusicProfile container="flac,mkv" codec="flac" />
        <PhotoProfile container="jpeg" />
      </DirectPlayProfiles>
      <CodecProfiles>
      <VideoCodec name="*">
         <Limitations>
           <UpperBound name="video.width" value="3840" />
           <UpperBound name="video.height" value="2160" />
           <UpperBound name="video.bitDepth" value="10" />
         </Limitations>
        </VideoCodec>
        <VideoAudioCodec name="*">
          <Limitations>
            <UpperBound name="audio.channels" value="8" />
          </Limitations>
        </VideoAudioCodec>
      </CodecProfiles>
    </Client>
  '';
in
{
  imports = [
    ./common.nix
  ];

  networking.hostName = "plex";

  services.plex = {
    enable = true;
    openFirewall = true;
    user = "plex";
    group = "plex";
    package = pkgs-unstable.plex;
  };

  users.users.plex.extraGroups = [ "video" "render" ];

  # Install the custom tvOS client profile (declared above) into PMS's
  # Profiles dir. PMS loads it at startup and it overrides the built-in
  # tvOS profile. why: docs/notes.md#hutch
  systemd.tmpfiles.rules = [
    "d ${config.services.plex.dataDir}/Plex\\x20Media\\x20Server/Profiles 0755 plex plex - -"
    "L+ ${config.services.plex.dataDir}/Plex\\x20Media\\x20Server/Profiles/tvOS.xml - - - - ${tvosProfile}"
  ];

  # QSV userspace stack; /dev/dri arrives via bind mount + allowedDevices
  # from hosts/hutch.nix. why: docs/notes.md#hutch
  hardware.graphics = {
    enable = true;
    extraPackages = with pkgs; [ intel-media-driver vpl-gpu-rt ];
  };
  environment.systemPackages = [ pkgs.libva-utils ];  # `vainfo` to verify QSV
}
