# Framework reinstall: Btrfs + LUKS + TPM2 auto-unlock

Target: Framework 13 AMD AI 300, `/dev/nvme0n1` (Samsung 990 EVO Plus 2TB).
Branch: `framework-reinstall`.

Result: power-on → no LUKS prompt (TPM unseals) → GDM login. Passphrase remains enrolled as fallback.

---

## 0. Before you start

- Branch `framework-reinstall` contains: `hardware/framework-disko.nix`, updated `chris-framework.nix`, stripped `hardware/framework.nix`, disko input in `flake.nix`.
- Darktable config backup is at `~/backups/darktable-config-*.tar.zst`. To move into `/mnt/Media/misc` (NFS, needs root):
  ```bash
  sudo mv ~/backups/darktable-config-*.tar.zst /mnt/Media/misc/
  ```
- Confirm any other things you want off this laptop are saved (browser profiles, ssh keys in `~/.ssh`, 1Password local data, GPG, etc.).
- Push the `framework-reinstall` branch to GitHub so the installer can clone it:
  ```bash
  git push -u origin framework-reinstall
  ```

## 1. Flash the installer to the SD card

ISO already downloaded: `~/Downloads/nixos-graphical-25.11.10470.0c88e1f2bdb9-x86_64-linux.iso`.

Identify the SD card device (it'll be `/dev/sdX`, NOT `nvme0n1`):

```bash
lsblk -o NAME,SIZE,TYPE,MOUNTPOINT,RM,MODEL
```

The current SD card at `/dev/sda` has photos on it (`DCIM/`). **Verify before flashing.** Unmount first:

```bash
umount /run/media/chris/disk
```

Flash (replace `sdX` with the correct device — getting this wrong wipes your data drive):

```bash
sudo dd if=~/Downloads/nixos-graphical-25.11.10470.0c88e1f2bdb9-x86_64-linux.iso \
        of=/dev/sdX bs=4M status=progress conv=fsync
sync
```

## 2. Boot the installer

1. Insert SD card into the Framework.
2. Power on, hammer **F12** for the boot menu.
3. Select the SD card. Secure Boot can stay on — NixOS 25.11 ISOs ship with shim.
4. Once GNOME loads, open a terminal.

## 3. Set up the live environment

```bash
sudo -i
# wifi (if needed)
nmcli device wifi connect "SSID" password "PASSPHRASE"

# tools
nix-shell -p git
```

## 4. Run disko (THIS WIPES /dev/nvme0n1)

Clone the repo into the live system (not `/mnt` yet — disko mounts at `/mnt`):

```bash
git clone -b framework-reinstall https://github.com/<you>/nix-config /tmp/nix-config
cd /tmp/nix-config
```

Run disko. It'll prompt for the new LUKS passphrase (twice). Pick a strong one — this is your fallback when TPM unseal fails.

```bash
nix --experimental-features "nix-command flakes" \
    run github:nix-community/disko/latest -- \
    --mode destroy,format,mount \
    ./hardware/framework-disko.nix
```

Verify:

```bash
lsblk
mount | grep /mnt
# expect: /mnt, /mnt/home, /mnt/nix, /mnt/persist, /mnt/snapshots, /mnt/swap, /mnt/boot
```

## 5. Generate hardware config

```bash
nixos-generate-config --no-filesystems --root /mnt
```

`--no-filesystems` is critical: disko owns `fileSystems`. Compare the generated `/mnt/etc/nixos/hardware-configuration.nix` against `hardware/framework.nix` in the repo — if kernel modules differ, update the repo file. Then commit:

```bash
cp /mnt/etc/nixos/hardware-configuration.nix /tmp/nix-config/hardware/framework.nix
# inspect, then if happy:
cd /tmp/nix-config
git add hardware/framework.nix
git -c user.email=chris@mcneill.fyi -c user.name=Chris commit -m "regen framework hardware config post-disko"
```

(Don't push yet — finish install first, push from the new system once you're sure it boots.)

## 6. Install

```bash
nixos-install --flake /tmp/nix-config#chris-framework --no-root-passwd
```

`--no-root-passwd` is fine because `users.users.chris` is declared. You'll be asked to set chris's password if it isn't hashed in the config — check `users.users.chris.hashedPassword` / `initialPassword`. If neither is set, drop the flag and let it prompt for root.

When done:

```bash
reboot
```

Pull the SD card. First boot will ask for the **LUKS passphrase** (TPM isn't enrolled yet) and then the user password.

## 7. Enrol the TPM (post-first-boot)

Log in, open a terminal:

```bash
# Confirm TPM is visible
sudo systemd-cryptenroll --tpm2-device=list

# Find the LUKS device
lsblk -o NAME,TYPE,MOUNTPOINT,UUID

# Enrol (will prompt for the passphrase you set during disko)
sudo systemd-cryptenroll \
    --tpm2-device=auto \
    --tpm2-pcrs=0+2+7 \
    /dev/disk/by-partlabel/luks
```

PCR choice:
- `0` firmware
- `2` extended firmware / option ROMs
- `7` Secure Boot state

If Secure Boot is **off**, drop PCR 7 (it's meaningless without it):
```
--tpm2-pcrs=0+2
```

Verify keyslots:

```bash
sudo cryptsetup luksDump /dev/disk/by-partlabel/luks | grep -E "Keyslot|tpm2"
```

Reboot. You should go straight to the GDM login screen with no LUKS prompt.

## 8. After firmware updates

Firmware updates change PCR 0/2 and break TPM unseal. Re-enrol:

```bash
sudo systemd-cryptenroll --wipe-slot=tpm2 /dev/disk/by-partlabel/luks
sudo systemd-cryptenroll --tpm2-device=auto --tpm2-pcrs=0+2+7 /dev/disk/by-partlabel/luks
```

Your passphrase still works as fallback during the gap.

## 9. Hibernate (optional)

Hibernate to the btrfs swapfile needs `resume_offset`:

```bash
sudo btrfs inspect-internal map-swapfile -r /swap/swapfile
```

Take the offset, uncomment + fill the two lines in `chris-framework.nix`:

```nix
boot.resumeDevice = "/dev/mapper/cryptroot";
boot.kernelParams = [ "resume_offset=<offset>" ];
```

`sudo nixos-rebuild switch --flake .#chris-framework`.

## 10. Merge the branch

Once you're happy:

```bash
git checkout main
git merge framework-reinstall
git push
```

---

## Troubleshooting

- **disko fails "device already in use"**: `sudo wipefs -a /dev/nvme0n1` then re-run disko.
- **`fileSystems."/" already defined`**: you ran `nixos-generate-config` without `--no-filesystems`, or `hardware/framework.nix` still has `fileSystems`. Strip them.
- **TPM unseal fails after a kernel update**: kernel/initrd are *not* in PCRs 0/2/7, so this shouldn't happen. If it does, check `systemctl status systemd-cryptsetup@cryptroot` — usually a firmware update sneaked in. Re-enrol.
- **No `/dev/disk/by-partlabel/luks`**: disko didn't set the partition label. Use `/dev/nvme0n1p2` instead, or fix `label = "luks";` in the disko config.
- **Want to add lanzaboote (proper Secure Boot)**: separate effort — install <https://github.com/nix-community/lanzaboote>, generate keys, enrol in BIOS, then PCR 7 becomes meaningful.
