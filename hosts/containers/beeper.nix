{ config, pkgs, pkgs-unstable, lib, ... }:

# Self-hosted Beeper bridges as a NixOS container on minihutch.
# Outbound-only: no Caddy vhost, no tunnel, no open ports.
# why: docs/notes.md#beeper-bridges

let
  stateDir = "/var/lib/beeper";
  bbctlConfig = "${stateDir}/bbctl.json";

  # bbctl >=0.14 (unstable) treats telegram as a Go bridge — no provisioning
  # proxy, no python-style launch. why: docs/notes.md#beeper-bridges
  bbctl = "${pkgs-unstable.beeper-bridge-manager}/bin/bbctl";

  # Signal-Server v20261104.0.0 made uploadLength mandatory on
  # GET /v4/attachments/form/upload, so every outgoing attachment failed with
  # a 400 ("failed to decode upload attributes"). Fixed upstream in
  # mautrix/signal#703 after v26.10; drop this once nixpkgs ships v26.11.
  # why: docs/notes.md#beeper-bridges
  mautrix-signal = pkgs-unstable.mautrix-signal.overrideAttrs (old: {
    patches = (old.patches or []) ++ [ ./mautrix-signal-upload-length.patch ];
  });

  # Go bridgev2 bridges not in nixpkgs, built from the upstream tag. Bump
  # version + both hashes to upgrade. Without a valid Tag in ldflags the
  # bridges panic at startup. why: docs/notes.md#beeper-bridges
  mkMautrixBridge = { name, version, hash, vendorHash }:
    pkgs.buildGoModule rec {
      pname = "mautrix-${name}";
      inherit version vendorHash;
      src = pkgs.fetchFromGitHub {
        owner = "mautrix";
        repo = name;
        rev = "v${version}";
        inherit hash;
      };
      subPackages = [ "cmd/mautrix-${name}" ];
      tags = [ "goolm" ];
      ldflags = [ "-s" "-w" "-X" "main.Tag=v${version}" "-X" "main.Commit=${src.rev}" ];
    };

  mautrix-telegram = mkMautrixBridge {
    name = "telegram";
    version = "0.2607.0";
    hash = "sha256-MpdsWtEsVnC6purF5sw+RD+Nb/3Wo0xrzSn2BuFZmj8=";
    vendorHash = "sha256-bmpTm1/6Z+kAFGAJ70ohBz8+n8JZk7mZyCfX0+FB/fE=";
  };

  mautrix-bluesky = mkMautrixBridge {
    name = "bluesky";
    version = "0.2510.0";
    hash = "sha256-tADkD2WSATOubXiLX76qoqFp5aOst62qx40TjhLN2os=";
    vendorHash = "sha256-4vX9KV2+TMxKkO7OGTazhDF9jx5/HNbenSUIN8qajLs=";
  };

  # name -> the command bbctl launches via --custom-startup-command.
  # signal/whatsapp/gmessages track unstable so they update on flake bumps.
  # See README "Beeper bridges" for add/remove and the login bootstrap.
  bridges = {
    signal    = "${mautrix-signal}/bin/mautrix-signal";
    whatsapp  = "${pkgs-unstable.mautrix-whatsapp}/bin/mautrix-whatsapp";
    telegram  = "${mautrix-telegram}/bin/mautrix-telegram";
    bluesky   = "${mautrix-bluesky}/bin/mautrix-bluesky";
    gmessages = "${pkgs-unstable.mautrix-gmessages}/bin/mautrix-gmessages";
  };

  mkBridgeService = name: command: {
    description = "Beeper self-hosted mautrix-${name} bridge";
    after = [ "network-online.target" ];
    wants = [ "network-online.target" ];
    wantedBy = [ "multi-user.target" ];
    # Stay inactive until `bbctl login` has been run once.
    unitConfig.ConditionPathExists = bbctlConfig;
    environment.BBCTL_CONFIG = bbctlConfig;
    serviceConfig = {
      User = "beeper";
      Group = "beeper";
      WorkingDirectory = stateDir;
      ExecStart = "${bbctl} run --no-update --custom-startup-command ${command} sh-${name}";
      # bbctl exits 0 when its startup whoami fails (e.g. DNS not up yet at
      # boot), so on-failure would leave the bridge down until the next deploy.
      Restart = "always";
      RestartSec = "30s";
    };
  };
in
{
  imports = [ ./common.nix ];

  # libolm: flagged insecure, required for end-to-bridge encryption.
  nixpkgs.config.permittedInsecurePackages = [ "olm-3.2.16" ];

  networking.hostName = "beeper";

  # Single service user owns the bbctl login token and all bridge state/DBs.
  users.users.beeper = {
    isSystemUser = true;
    group = "beeper";
    home = stateDir;
    createHome = true;
  };
  users.groups.beeper = {};

  systemd.tmpfiles.rules = [
    "d ${stateDir} 0750 beeper beeper - -"
  ];

  environment.systemPackages = (with pkgs-unstable; [
    mautrix-whatsapp
    mautrix-gmessages
    beeper-bridge-manager
  ]) ++ [ mautrix-signal mautrix-telegram mautrix-bluesky ];

  systemd.services = lib.mapAttrs'
    (name: command: lib.nameValuePair "mautrix-${name}" (mkBridgeService name command))
    bridges;
}
