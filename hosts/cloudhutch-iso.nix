# Installer ISO for cloudhutch (x86_64). Built only, never deployed.
#
# The live system gets the same static IPv6 address as the installed host, so
# it is reachable over the public IPv6 as soon as it boots. It also bakes in
# the disko config and a Nix daemon wrapper rooted at /mnt, letting the laptop
# copy the system closure straight onto the target disk instead of into the
# RAM-backed live store.
#
# Build on the x86_64 laptop:
#   nix build .#nixosConfigurations.cloudhutch-iso.config.system.build.isoImage
{ config, pkgs, lib, modulesPath, ... }:

let
  keys = import ../modules/keys.nix;
in
{
  imports = [
    "${modulesPath}/installer/cd-dvd/installation-cd-minimal.nix"
    ../modules/locale.nix
    # Static IPv6 WAN + systemd-networkd/resolved.
    ../modules/cloudhutch-network.nix
  ];

  networking.hostName = "cloudhutch-iso";
  # The installer profile enables NetworkManager; this image uses networkd so
  # the static IPv6 configuration applies without NM fighting it.
  networking.networkmanager.enable = lib.mkForce false;

  # SSH so the install can be driven from the laptop over IPv6.
  services.openssh = {
    enable = true;
    openFirewall = true;
    settings = {
      PermitRootLogin = "prohibit-password";
      PasswordAuthentication = false;
      KbdInteractiveAuthentication = false;
    };
  };
  users.users.nixos.openssh.authorizedKeys.keys = [ keys.chris ];
  users.users.root.openssh.authorizedKeys.keys = [ keys.chris ];

  environment.systemPackages = with pkgs; [
    disko
    git
    curl
  ];

  # Partition layout is available offline on the live system.
  environment.etc."cloudhutch-disko.nix".source = ../hardware/cloudhutch-disko.nix;

  # Nix daemon that operates on the *target* store mounted at /mnt. Used by
  # `nix copy --to ssh-ng://root@[v6]?remote-program=/etc/nix-daemon-mnt`,
  # which keeps the multi-GB closure out of the ISO's RAM-backed store.
  environment.etc."nix-daemon-mnt" = {
    mode = "0755";
    text = ''
      #!${pkgs.runtimeShell}
      exec ${config.nix.package}/bin/nix --store 'local?root=/mnt' daemon --stdio "$@"
    '';
  };

  # Unsigned, locally built closures are copied to this live system.
  nix.settings = {
    experimental-features = [ "nix-command" "flakes" ];
    require-sigs = false;
    sandbox = false;
  };

  boot.kernelParams = [ "console=tty0" "console=ttyS0,115200n8" ];

  system.stateVersion = "26.05";
}
