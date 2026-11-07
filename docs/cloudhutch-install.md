# cloudhutch install

Target: IPv6-only **x86_64** netcup KVM VPS, **2a0a:4cc0:c0:37f8::1/64**,
gateway `fe80::1`, managed over the tailnet after first boot.

This is a **minimal tailnet node**, not a container host. It runs OpenSSH and
Tailscale only, and advertises itself as an IPv6-only exit node; services can
be added later.

The public interface has no IPv4. Everything that needs IPv4 (GitHub, flake
inputs) is fetched on the laptop and copied to the VPS. See
`docs/notes.md#cloud-vps-ipv6-only` for why.

---

## 0. Before you start

Confirm the IPv6 address in netcup's SCP. This runbook assumes the first
address in the assigned /64:

```nix
# modules/cloudhutch-network.nix
address = "2a0a:4cc0:c0:37f8::1";
```

If netcup assigned a different address inside the /64, change it there. The
same module feeds the installed host and the installer ISO, so this must be
right before building.

You also need:

- netcup SCP access (to upload the ISO and open the VNC console).
- IPv6 connectivity on the laptop (the whole install path is public IPv6).
- An **x86_64 build host** — the laptop matches the VPS, so no cross-build or
  binfmt setup is needed.
- A Tailscale auth key for first boot — preferably ephemeral or reusable, from
  the Tailscale admin console. It is used once and is not stored in this repo.

## 1. Build the installer ISO

Both `cloudhutch` and `cloudhutch-iso` are `x86_64-linux`, matching the
laptop. No emulation is involved.

```bash
nix build .#nixosConfigurations.cloudhutch-iso.config.system.build.isoImage
ls result/iso/
```

The ISO boots with:

- static IPv6 from `modules/cloudhutch-network.nix`
- OpenSSH, key-only, for `root` and `nixos`
- `disko`, `git`, `curl`
- the disko config at `/etc/cloudhutch-disko.nix`
- `/etc/nix-daemon-mnt`, a Nix daemon rooted at `local?root=/mnt`

## 2. Upload and boot the ISO

In netcup SCP:

1. **Media → Images → Custom ISO upload**, upload `result/iso/*.iso`.
2. Mount it as the server's DVD.
3. Boot the x86_64 server in UEFI mode and open the VNC console.

The image is an x86_64 NixOS ISO. Uploading an ARM ISO to this server will
not boot.

## 3. Verify the live network and SSH in

On the VNC console:

```bash
ip -6 addr show
ip -6 route show
ping -6 -c2 2606:4700:4700::1111
```

You should see `2a0a:4cc0:c0:37f8::1/64`, a default route via `fe80::1`, and
a working ping. Then from the laptop:

```bash
ssh -o StrictHostKeyChecking=accept-new root@2a0a:4cc0:c0:37f8::1
```

If SSH does not come up, use the VNC console. The ISO intentionally does not
carry Tailscale; it keeps the image lean.

## 4. Partition the disk

Confirm how netcup presented the disk:

```bash
lsblk -o NAME,SIZE,TYPE,MODEL
```

The layout assumes `/dev/vda` (virtio-blk). Some netcup images expose
`/dev/sda` (virtio-scsi); if so, edit `hardware/cloudhutch-disko.nix`, rebuild
the ISO, and restart from step 2.

**This wipes the target disk:**

```bash
disko --mode destroy,format,mount /etc/cloudhutch-disko.nix
```

Verify:

```bash
lsblk
mount | grep /mnt
# expect: /mnt, /mnt/nix, /mnt/persist, /mnt/swap, /mnt/boot
```

## 5. Build locally and copy the closure straight to /mnt

On the laptop (this builds the matching x86_64 closure):

```bash
closure=$(nix build .#nixosConfigurations.cloudhutch.config.system.build.toplevel --print-out-paths)
echo "$closure"

nix copy --no-check-sigs \
  --to 'ssh-ng://root@[2a0a:4cc0:c0:37f8::1]?remote-program=/etc/nix-daemon-mnt' \
  "$closure"
```

The `remote-program` wrapper makes Nix write into the VPS's `/mnt` store
instead of the live ISO's RAM-backed store. Without it, a multi-GB closure can
exhaust a small VPS's memory.

## 6. Install offline

Still on the laptop:

```bash
ssh root@2a0a:4cc0:c0:37f8::1 \
  "nixos-install --root /mnt --system '$closure' \
     --no-root-passwd --no-channel-copy"
```

No network is needed: the closure is already in `/mnt/nix/store`.
`--no-channel-copy` avoids trying to copy a nixpkgs channel.

Set an interactive password for `chris` before rebooting (SSH uses keys, but
the VNC console needs a password):

```bash
ssh -t root@2a0a:4cc0:c0:37f8::1 \
  'nixos-enter --root /mnt -c "passwd chris"'
```

Reboot:

```bash
ssh root@2a0a:4cc0:c0:37f8::1 reboot
```

## 7. First boot: join the tailnet

The installed system comes up on the same IPv6 address, but public SSH is
closed by `hosts/cloudhutch.nix` (`services.openssh.openFirewall = false`).
Use the netcup VNC console, log in as `chris` with the password set in step 6,
and authenticate Tailscale:

```bash
sudo tailscale up --authkey='<key>'
tailscale status
```

If you prefer to bootstrap over SSH instead of VNC, temporarily set
`services.openssh.openFirewall = true`, install that closure, authenticate
Tailscale, then deploy the final closed configuration. Do not leave public 22
open in the steady-state config.

The host config advertises an exit node. `extraSetFlags` reapplies
`--advertise-exit-node` on every activation, but if it has not taken effect
yet:

```bash
sudo tailscale set --advertise-exit-node
```

Approve the exit node in the Tailscale admin console under **Machines →
cloudhutch → Edit route settings**. The node is IPv6-only: clients can exit
IPv6 traffic through it, but IPv4 has no upstream until NAT64/DNS64 or an IPv4
tunnel is added.

## 8. Deploy from the laptop

Add the host key, then deploy over the tailnet:

```bash
ssh-keyscan cloudhutch >> ~/.ssh/known_hosts

deploy .#cloudhutch --dry-activate
deploy .#cloudhutch
```

`cloudhutch` resolves through tailnet MagicDNS. If MagicDNS is disabled, set
`address` in `lib/network.nix` to the Tailscale IP or full
`cloudhutch.<tailnet>.ts.net` name instead.

The deploy node sets `remoteBuild = false`, so deploy-rs builds the x86_64
closure on the laptop and copies it. It will not try to compile on the VPS.
This first deploy also closes public port 22; confirm tailnet SSH works before
relying on it, with netcup VNC as the fallback.

## 9. Verify

```bash
ssh cloudhutch 'ip -6 addr show; ip -6 route show'
ssh cloudhutch 'systemctl status tailscaled --no-pager'
ssh cloudhutch 'sudo nixos-rebuild list-generations'

deploy .#cloudhutch --dry-activate
```

Then from another tailnet machine, confirm the node is visible:

```bash
tailscale status | grep cloudhutch
```

## Troubleshooting

**No IPv6 at boot**
- VNC in and check `ip -6 addr`, `ip -6 route`.
- The gateway must be `fe80::1` with `GatewayOnLink = true`; that is set in
  `modules/cloudhutch-network.nix`.
- If netcup assigned a different host address, fix `address` and rebuild the
  ISO.

**ISO boots but the installer can't be reached**
- Check netcup's firewall/console settings for IPv6.
- The ISO has no Tailscale, so public IPv6 SSH is the only remote path. The
  VNC console always works.

**UEFI doesn't find the installed system**
- `boot.loader.efi.canTouchEfiVariables = false` installs the fallback
  `EFI/BOOT/BOOTX64.EFI` on x86_64. If netcup's firmware insists on NVRAM,
  set it to `true` in `hosts/cloudhutch.nix`, reinstall (or deploy and reboot).

**ISO boots to a blank screen or firmware shell**
- Confirm the uploaded image is the x86_64 ISO, not the old ARM64 one.
- Check that the server is booting in UEFI mode and the ISO is mounted as DVD.

**`nix copy` says a path is not valid on the remote**
- The remote-program wrapper must exist at `/etc/nix-daemon-mnt` on the live
  ISO. Rebuild the ISO if it is missing.
- Run `disko` before `nix copy`; the wrapper writes to `/mnt/nix/store`.

**`deploy` can't resolve `cloudhutch`**
- MagicDNS may be off. Set `address` in `lib/network.nix` to the node's
  Tailscale IP (`tailscale status` on the VPS) and re-run home-manager on the
  laptop.

**On-box `nix flake update` or `nixos-rebuild` hangs**
- Expected on an IPv6-only host: GitHub is IPv4-only. Build on the laptop and
  deploy. If you need on-box access, arrange NAT64/DNS64 or an IPv4 egress
  path first.
