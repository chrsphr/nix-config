# minihutch install + cutover

Target: second baremetal container host, **192.168.1.3**, btrfs boot drive via
disko, no LUKS/TPM (same as hutch — it's a box in the house, not a laptop).

Result: `deploy .#minihutch` brings up **beeper, caddy, pihole-2, tailscale and
uptime** as systemd-nspawn containers on `.3`, and those five stop existing on
hutch.

This is a **move, not a duplication**: the five services keep their existing
IPs (.40, .239, .10, .207, .31), so hutch's copies must be gone before
minihutch's come up, or two machines will answer for the same addresses.

---

## 0. Before you start

Fill in the two placeholders the config can't know:

| Placeholder | File | Find it with |
|---|---|---|
| boot disk device | `hardware/minihutch-disko.nix` (`/dev/nvme0n1`) | `lsblk -o NAME,SIZE,TYPE,MODEL` on the live ISO |
| onboard NIC MAC | `hosts/minihutch.nix` (`containerHost.macAddress = null`) | `ip -br link` on the live ISO |
| swapfile size | `hardware/minihutch-disko.nix` (`64G`) | size to actual RAM; hutch's 64G assumes 128G |

Also confirm you have, off-box:

- The **caddy** age key (`/var/lib/sops-nix/caddy/keys.txt` on hutch) and the
  **uptime** one (a copy of the laptop master key — also in 1Password). Both
  are needed in step 7; neither is in the repo.
- A copy of **`/var/lib/beeper/`** from hutch's beeper container. That's the
  bbctl login token plus every bridge's SQLite DB, and it is not in sops or
  the repo. Without it you re-run the `bbctl login` bootstrap and lose bridge
  history — see the README "Beeper bridges" section.

Push the branch so the installer can clone it.

## 1. Boot the installer

Build and flash the repo's own ISO (SSH-enabled, chris's key preinstalled):

```bash
nix build .#nixosConfigurations.install-iso.config.system.build.isoImage
sudo dd if=result/iso/*.iso of=/dev/sdX bs=4M status=progress conv=fsync   # VERIFY sdX
```

Boot minihutch off it, cable **one** port for now (the bond is active-backup;
extra cables can wait until it's up).

## 2. Fill in the hardware facts

On the live system:

```bash
lsblk -o NAME,SIZE,TYPE,MODEL     # -> boot disk device
ip -br link                       # -> MAC of the port you cabled
free -g                           # -> swap sizing
```

Edit `hardware/minihutch-disko.nix` and `hosts/minihutch.nix` accordingly and
commit — Nix only sees git-tracked files.

## 3. Run disko (THIS WIPES THE TARGET DISK)

```bash
sudo -i
nix-shell -p git
git clone -b <branch> https://github.com/<you>/nix-config /tmp/nix-config
cd /tmp/nix-config

nix --experimental-features "nix-command flakes" \
    run github:nix-community/disko/latest -- \
    --mode destroy,format,mount \
    ./hardware/minihutch-disko.nix
```

Verify:

```bash
lsblk
mount | grep /mnt
# expect: /mnt, /mnt/nix, /mnt/persist, /mnt/snapshots, /mnt/swap, /mnt/boot
```

`/mnt/snapshots` matters — `modules/container-snapshots.nix` writes the nightly
container-root snapshots there.

## 4. Regenerate the hardware config

`hardware/minihutch.nix` in the repo is copied from hutch, not scanned from
this machine. Replace it:

```bash
nixos-generate-config --no-filesystems --root /mnt
cp /mnt/etc/nixos/hardware-configuration.nix /tmp/nix-config/hardware/minihutch.nix
```

`--no-filesystems` is critical: disko owns `fileSystems`. Re-add the header
comment, inspect the diff, then commit.

## 5. Install

```bash
nixos-install --flake /tmp/nix-config#minihutch --no-root-passwd
```

`--no-root-passwd` is fine — `users.users.deploy` and `users.users.chris` are
declared with chris's SSH key. Set chris's console password before rebooting,
since nothing in the repo does (deliberately — see the comment in
`hosts/minihutch.nix`):

```bash
nixos-enter --root /mnt -c 'passwd chris'
reboot
```

Containers will start on this first boot and **collide with hutch's**. Either
do step 6 first, or accept a few minutes of duplicate-IP weirdness on the LAN.

## 6. Cutover: take the five services off hutch

The `parent` flip in `lib/network.nix` is already committed, so hutch simply
stops declaring them. Deploy hutch **first**:

```bash
deploy .#hutch
```

Then confirm they're really gone (nspawn does not remove a container's root
just because the config stopped declaring it):

```bash
ssh deploy@192.168.1.2 machinectl list
# expect: gb-grid immich network-optimizer pihole-1 plex sonarr transmission
```

If any of beeper/caddy/pihole-2/tailscale/uptime are still running:

```bash
ssh deploy@192.168.1.2 'sudo machinectl terminate <name>'
```

The stale roots under `/var/lib/nixos-containers/<name>` on hutch are your
rollback copy — **keep them until minihutch is verified**, then delete with
`sudo btrfs subvolume delete`. Their nightly snapshots in
`/snapshots/containers/<name>/` stop being taken but are not pruned.

## 7. Place the sops keys on minihutch

`containerHost.withSecrets = [ "caddy" "uptime" ]` creates
`/var/lib/sops-nix/{caddy,uptime}/` (mode 0700, root) and bind-mounts each
read-only into its container at `/var/secrets`. The key files themselves are
manual:

```bash
# from hutch, or from 1Password
ssh root@192.168.1.2 cat /var/lib/sops-nix/caddy/keys.txt  | \
  ssh root@192.168.1.3 'install -m600 -D /dev/stdin /var/lib/sops-nix/caddy/keys.txt'
ssh root@192.168.1.2 cat /var/lib/sops-nix/uptime/keys.txt | \
  ssh root@192.168.1.3 'install -m600 -D /dev/stdin /var/lib/sops-nix/uptime/keys.txt'
```

Note what this means: the **laptop master key now lives on two boxes**, since
uptime decrypts with a copy of it (see `.sops.yaml`). Compromising either box
exposes every secret. Issuing minihutch its own key and re-running
`sops updatekeys` is the fix if that stops being acceptable.

Restart the two containers so sops-nix re-runs activation with the keys
present:

```bash
ssh deploy@192.168.1.3 'sudo machinectl reboot caddy; sudo machinectl reboot uptime'
```

## 8. Restore beeper state

```bash
rsync -a root@192.168.1.2:/var/lib/nixos-containers/beeper/var/lib/beeper/ \
         root@192.168.1.3:/var/lib/nixos-containers/beeper/var/lib/beeper/
ssh root@192.168.1.3 'systemd-run -M beeper --wait chown -R beeper:beeper /var/lib/beeper'
ssh deploy@192.168.1.3 'sudo machinectl reboot beeper'
```

The `mautrix-*` units have `ConditionPathExists=/var/lib/beeper/bbctl.json`, so
they stay inactive until the token file is there and then start on their own.

## 9. Verify

```bash
ssh deploy@192.168.1.3 machinectl list
# expect: beeper caddy pihole-2 tailscale uptime

# caddy is serving and has a cert
curl -sI https://uptime.mcneill.fyi | head -1

# pihole-2 resolving
dig +short google.com @192.168.1.10

# tailscale is up and still advertising the subnet route
ssh root@192.168.1.3 'systemd-run -M tailscale --wait tailscale status'

# bridges
ssh root@192.168.1.3 'systemd-run -M beeper --wait systemctl status "mautrix-*"'
```

Gatus (`uptime.mcneill.fyi`) is the real check — every endpoint in
`lib/network.nix` should go green. Note the moved services still carry the
`group = "Hutch Primary Services"` label in `lib/network.nix`; rename it there
if the dashboard grouping now reads wrong.

Tailscale specifically: `--advertise-routes=192.168.1.0/24` is re-advertised
from a new node, so **re-approve the subnet route in the Tailscale admin
console** — it will not be auto-approved just because the old node had it.

## 10. Steady state

```bash
deploy .#minihutch            # deploys all five containers with it
deploy .#minihutch --dry-activate
```

Magic rollback is disabled fleet-wide (see `flake.nix`), so verify by checking
services after a deploy; minihutch's physical console is the recovery path.

Once verified, delete the stale container roots on hutch (step 6) and set
`containerHost.macAddress` if you left it null.
