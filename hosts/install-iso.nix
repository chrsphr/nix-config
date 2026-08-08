# Minimal installer ISO with SSH enabled for key-only remote installs.
{ modulesPath, pkgs, ... }:

let
  keys = import ../modules/keys.nix;
in
{
  imports = [
    "${modulesPath}/installer/cd-dvd/installation-cd-minimal.nix"
    ../modules/locale.nix
  ];

  # SSH server so the installer can be driven remotely.
  services.openssh = {
    enable = true;
    settings = {
      # Root key auth only; password auth stays off for passwordless installs.
      PermitRootLogin = "prohibit-password";
      PasswordAuthentication = false;
    };
  };

  # Installer user's key too — the ISO's default `nixos` user is the one you
  # log in as, so both need the key to survive the shell round-trip.
  users.users.nixos.openssh.authorizedKeys.keys = [ keys.chris ];

  # Git for cloning this flake onto the target during install.
  environment.systemPackages = with pkgs; [ git ];

  # Enable flakes on the live system so `nixos-install --flake` works without
  # NIX_CONFIG exports (the minimal ISO disables them by default).
  nix.settings.experimental-features = [ "nix-command" "flakes" ];

  system.stateVersion = "26.05";
}
