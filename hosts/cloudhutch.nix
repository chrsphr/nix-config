{ pkgs, ... }:

# cloudhutch: IPv6-only x86_64 netcup VPS, managed over the tailnet.
#
# Minimal role on purpose — SSH and Tailscale only, no containers, no Caddy,
# no sops secrets. Services can be added later; the install runbook is
# docs/cloudhutch-install.md and the decision record is
# docs/notes.md#cloud-vps-ipv6-only.

let
  keys = import ../modules/keys.nix;
in
{
  imports = [
    ../modules/locale.nix
    ../hardware/cloudhutch.nix
    # Static IPv6 WAN + systemd-networkd/resolved.
    ../modules/cloudhutch-network.nix
  ];

  networking.hostName = "cloudhutch";

  # netcup presents the boot disk as virtio (/dev/vda); see
  # hardware/cloudhutch-disko.nix. UEFI install with the fallback bootloader
  # because VPS firmware does not always persist NVRAM entries.
  boot.loader = {
    systemd-boot.enable = true;
    systemd-boot.configurationLimit = 5;
    efi.canTouchEfiVariables = false;
  };
  # tty0 for netcup's VNC console, ttyS0 for serial rescue.
  boot.kernelParams = [ "console=tty0" "console=ttyS0,115200n8" ];

  # SSH + deploy user for deploy-rs. Keys only. No public 22: management is
  # over the tailnet, and the netcup VNC console is the out-of-band fallback.
  services.openssh = {
    enable = true;
    openFirewall = false;
    settings = {
      PermitRootLogin = "no";
      PasswordAuthentication = false;
      KbdInteractiveAuthentication = false;
    };
  };
  users.users.deploy = {
    isNormalUser = true;
    extraGroups = [ "wheel" ];
    openssh.authorizedKeys.keys = [ keys.chris ];
  };
  # chris: interactive login. Password set imperatively on the box on purpose,
  # same as the other servers.
  users.users.chris = {
    isNormalUser = true;
    uid = 1001;
    extraGroups = [ "wheel" ];
    openssh.authorizedKeys.keys = [ keys.chris ];
  };
  users.users.root.openssh.authorizedKeys.keys = [ keys.chris ];
  security.sudo.wheelNeedsPassword = false;

  # Tailnet membership for management, plus exit-node service. tailscaled is
  # authenticated by hand after first boot (docs/cloudhutch-install.md), so no
  # auth key lives in the repo.
  #
  # useRoutingFeatures = "server" enables IPv4/IPv6 forwarding. The VPS is
  # IPv6-only, so exit-node clients can route IPv6 through it but have no IPv4
  # upstream until NAT64/DNS64 or an IPv4 tunnel is added.
  services.tailscale = {
    enable = true;
    openFirewall = true;
    useRoutingFeatures = "server";
    # extraUpFlags only applies when authKeyFile is set; extraSetFlags is
    # re-applied on every activation. Keep both identical if an auth key is
    # ever added, so a manual `tailscale up` cannot drop the exit-node flag.
    extraUpFlags = [ "--advertise-exit-node" ];
    extraSetFlags = [ "--advertise-exit-node" ];
  };
  networking.firewall = {
    trustedInterfaces = [ "tailscale0" ];
    # Tailscale return traffic arrives on a different interface.
    checkReversePath = "loose";
  };

  # deploy-rs copies unsigned x86_64 closures built on the laptop to this
  # host. The VPS is IPv6-only, so it cannot fetch GitHub itself.
  nix.settings = {
    experimental-features = [ "nix-command" "flakes" ];
    require-sigs = false;
  };
  # Small VPS disk: keep generations and the store from growing forever.
  nix.gc = {
    automatic = true;
    dates = "weekly";
    options = "--delete-older-than 14d";
  };
  nix.optimise.automatic = true;

  environment.systemPackages = with pkgs; [
    vim
    htop
    git
    curl
  ];

  system.stateVersion = "26.05";
}
