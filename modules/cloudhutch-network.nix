# cloudhutch's IPv6-only WAN configuration.
#
# Shared by the installed host and the installer ISO so the live system comes
# up on the same address and can be reached over the public IPv6 immediately.
# netcup switches the /64 to the VM; fe80::1 is the link-local gateway.
#
# The host address is the first address in the assigned /64. Verify it in
# netcup's SCP before building the ISO — if they assigned another address,
# change `address` here and rebuild.
{ ... }:

let
  address = "2a0a:4cc0:c0:37f8::1";
  prefixLength = 64;
  gateway = "fe80::1";
  # Cloudflare's IPv6 resolvers. netcup's own DNS servers are IPv4-only.
  nameservers = [
    "2606:4700:4700::1111"
    "2606:4700:4700::1001"
  ];
in
{
  networking = {
    enableIPv6 = true;
    # No IPv4 on the public interface. Tailscale still creates its own
    # 100.64.0.0/10 address on tailscale0, which is unrelated to this NIC.
    useDHCP = false;
    useNetworkd = true;
    firewall.enable = true;
  };

  services.resolved.enable = true;

  systemd.network.networks."10-wan" = {
    # Match any physical/virtual ethernet NIC, whatever name netcup's virtio
    # device gets (ens3, enp1s0, ...). Kind=!* skips bonds/bridges/veths.
    matchConfig = {
      Type = "ether";
      Kind = "!*";
    };

    address = [ "${address}/${toString prefixLength}" ];
    DHCP = "no";
    dns = nameservers;

    networkConfig = {
      # Need a link-local address for the fe80::1 gateway, but no IPv4 LL.
      LinkLocalAddressing = "ipv6";
      IPv6AcceptRA = false;
    };

    routes = [
      {
        Destination = "::/0";
        Gateway = gateway;
        # fe80::1 is on-link; without this systemd-networkd treats it as a
        # routed gateway and the route never installs.
        GatewayOnLink = true;
      }
    ];
  };
}
