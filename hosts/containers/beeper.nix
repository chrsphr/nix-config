{ config, pkgs, lib, ... }:

# Self-hosted Beeper bridges as a NixOS container on minihutch.
# Outbound-only: no Caddy vhost, no tunnel, no open ports.
# why: docs/notes.md#beeper-bridges

let
  stateDir = "/var/lib/beeper";
  bbctlConfig = "${stateDir}/bbctl.json";

  # Forward the real HTTP method through bbctl's provisioning proxy (it
  # hardcodes PUT, breaking telegram). why: docs/notes.md#beeper-bridges
  bbctl-patched = pkgs.beeper-bridge-manager.overrideAttrs (old: {
    postPatch = (old.postPatch or "") + ''
      substituteInPlace cmd/bbctl/proxy.go \
        --replace-fail \
        'http.NewRequestWithContext(cmd.Ctx, http.MethodPut, fullURL.String(), body)' \
        'http.NewRequestWithContext(cmd.Ctx, reqData.Method, fullURL.String(), body)'
    '';
  });
  bbctl = "${bbctl-patched}/bin/bbctl";

  # Go bridgev2 telegram, built from the upstream tag (nixpkgs only has the
  # old Python bridge). Bump version + both hashes to upgrade.
  # why: docs/notes.md#beeper-bridges
  mautrix-telegram = pkgs.buildGoModule rec {
    pname = "mautrix-telegram";
    version = "0.2606.0";
    src = pkgs.fetchFromGitHub {
      owner = "mautrix";
      repo = "telegram";
      rev = "v${version}";
      hash = "sha256-tKoqtGCkUtCT/SMxRX6LzivGu0p/AM6TPDQoW9plTyE=";
    };
    vendorHash = "sha256-+VDdJg5RZzMrphJ5SK+YbdENhPiHJpwGY/JqBJewtUo=";
    subPackages = [ "cmd/mautrix-telegram" ];
    tags = [ "goolm" ];
    ldflags = [ "-s" "-w" "-X" "main.Tag=v${version}" "-X" "main.Commit=${src.rev}" ];
  };

  # bbctl launches telegram python-style (`-m module`); strip that for the Go
  # binary. why: docs/notes.md#beeper-bridges
  telegramCmd = pkgs.writeShellScript "mautrix-telegram-bbctl" ''
    if [ "$1" = "-m" ]; then shift 2; fi
    exec ${mautrix-telegram}/bin/mautrix-telegram "$@"
  '';

  # Bluesky isn't in nixpkgs; built from the upstream tag. Bump version +
  # both hashes to upgrade.
  mautrix-bluesky = pkgs.buildGoModule rec {
    pname = "mautrix-bluesky";
    version = "0.2510.0";
    src = pkgs.fetchFromGitHub {
      owner = "mautrix";
      repo = "bluesky";
      rev = "v${version}";
      hash = "sha256-tADkD2WSATOubXiLX76qoqFp5aOst62qx40TjhLN2os=";
    };
    vendorHash = "sha256-4vX9KV2+TMxKkO7OGTazhDF9jx5/HNbenSUIN8qajLs=";
    subPackages = [ "cmd/mautrix-bluesky" ];
    tags = [ "goolm" ];
    # Without a valid Tag the bridge panics at startup.
    ldflags = [ "-s" "-w" "-X" "main.Tag=v${version}" "-X" "main.Commit=${src.rev}" ];
  };

  # name -> the command bbctl launches via --custom-startup-command.
  # See README "Beeper bridges" for add/remove and the login bootstrap.
  bridges = {
    signal    = "${pkgs.mautrix-signal}/bin/mautrix-signal";
    whatsapp  = "${pkgs.mautrix-whatsapp}/bin/mautrix-whatsapp";
    telegram  = "${telegramCmd}";
    bluesky   = "${mautrix-bluesky}/bin/mautrix-bluesky";
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
      Restart = "on-failure";
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

  environment.systemPackages = (with pkgs; [
    mautrix-whatsapp
    mautrix-signal
  ]) ++ [ bbctl-patched mautrix-telegram mautrix-bluesky ];

  systemd.services = lib.mapAttrs'
    (name: command: lib.nameValuePair "mautrix-${name}" (mkBridgeService name command))
    bridges;
}
