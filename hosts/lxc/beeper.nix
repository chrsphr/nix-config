{ config, pkgs, lib, ... }:

let
  hostsLib = import ../../lib/network.nix { inherit lib; };

  stateDir = "/var/lib/beeper";
  bbctlConfig = "${stateDir}/bbctl.json";
  bbctl = "${pkgs.beeper-bridge-manager}/bin/bbctl";

  # Telegram: as of v26.04 (calver tag v0.26xx.0) the bridge is a Go bridgev2
  # rewrite, so — like signal/whatsapp — it speaks the /provision/v3 API, reports
  # remote-connection state to Beeper (shows up + manageable in the app), and
  # needs no Python-interpreter wrapper. nixpkgs still only ships the old Python
  # 0.15.3, so build the Go bridge from the upstream tagged release, same pattern
  # as bluesky below. The Go bridge auto-migrates the Python DB/config in place on
  # first start (cmd/mautrix-telegram/legacymigrate.{go,sql}). Bump version + both
  # hashes to upgrade.
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

  # bbctl still classifies `sh-telegram` as the *Python* bridge server-side, so it
  # launches the custom command python-style: `<cmd> -m mautrix_telegram -c config.yaml`.
  # The Go binary doesn't understand `-m` (it exits with "Unknown flag: m"), so we
  # keep a thin wrapper that strips the leading `-m <module>` and forwards the rest
  # (`-c config.yaml`) to the real Go entrypoint. Same trick as before, now pointing
  # at the Go bridge instead of Python.
  telegramCmd = pkgs.writeShellScript "mautrix-telegram-bbctl" ''
    if [ "$1" = "-m" ]; then shift 2; fi
    exec ${mautrix-telegram}/bin/mautrix-telegram "$@"
  '';

  # Bluesky is a Go bridgev2 bridge but isn't packaged in nixpkgs, so build it
  # from the upstream tagged release (pure-Go `goolm`, no libolm/CGO). Bump
  # version + both hashes to upgrade.
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
    # The bridge embeds its version via ldflags; without a valid tag it panics
    # at startup ("invalid semver: unknown") converting the version to calver.
    ldflags = [ "-s" "-w" "-X" "main.Tag=v${version}" "-X" "main.Commit=${src.rev}" ];
  };

  # (Dropped 2026-07-30) v26.06 needed a postPatch adding the
  # usernameChangeSyncMessage device capability, without which Signal's server
  # rejected linking a new device with `409 Conflict`. v26.07 declares it
  # upstream in signalCapabilities (pkg/signalmeow/provisioning.go), so plain
  # pkgs.mautrix-signal is used below.

  # Self-hosted Beeper bridges, as name -> the command bbctl should launch via
  # --custom-startup-command (which disables all downloads — nothing non-Nix ever
  # runs). signal and whatsapp are Go bridgev2 binaries straight from nixpkgs;
  # telegram/bluesky are Go bridgev2 bridges built from source above.
  # See the README "Beeper bridges" section for how to add/remove a bridge and the
  # one-time login bootstrap.
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
    # Stay inactive until `bbctl login` has been run once (token file present),
    # so the unit doesn't fail-loop before the one-time bootstrap.
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
  imports = [ ./common-lxc.nix ];

  # The mautrix bridges pull in libolm (Matrix E2EE), which nixpkgs flags as
  # insecure/unmaintained. Required for end-to-bridge encryption.
  nixpkgs.config.permittedInsecurePackages = [ "olm-3.2.16" ];

  networking = hostsLib.mkStaticNetwork "beeper" // {
    hostName = "beeper";
  };

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
    beeper-bridge-manager
    mautrix-whatsapp
    mautrix-signal
  ]) ++ [ mautrix-telegram mautrix-bluesky ];

  systemd.services = lib.mapAttrs'
    (name: command: lib.nameValuePair "mautrix-${name}" (mkBridgeService name command))
    bridges;

  # ── One-time bootstrap (imperative, run on the box) ────────────────────────
  # 1. sudo -u beeper env HOME=/var/lib/beeper \
  #      BBCTL_CONFIG=/var/lib/beeper/bbctl.json bbctl login
  #    (interactive email-code login; writes the token to bbctl.json and flips
  #    the ConditionPathExists so the services can start).
  # 2. systemctl start mautrix-signal mautrix-whatsapp mautrix-telegram mautrix-bluesky
  # 3. In the Beeper app, message each bridge bot (@sh-signalbot, @sh-whatsappbot,
  #    @sh-telegrambot, @sh-blueskybot) and follow `login`.
  # See the README "Beeper bridges" section for the full runbook.
}
