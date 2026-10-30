# Installing a host

Installs run from a fleet machine with nix-secrets access (voyager) against a target booted from the cosmos installer ISO. `install-host` wraps [nixos-anywhere](https://github.com/nix-community/nixos-anywhere): it partitions with the host's disko layout, installs the closure built locally, and places the host's SSH key, which is also its sops identity, before first boot.

## Build the installer

```bash
nix build .#installer-iso
sudo dd if=result/iso/*.iso of=/dev/sdX bs=4M conv=fsync status=progress
```

The ISO is the NixOS minimal installer with the latest kernel and no ZFS, plus `nixos-facter`, `git` and `pv`. Root is reachable over SSH with the keys in `modules/den/aspects/core/_ssh-keys/authorized.nix` (the device key and the YubiKeys). It carries no secrets and no NetBird: reach it over the LAN.

## Prepare the target

1. Firmware: Secure Boot **off** (GRUB is unsigned).
2. Boot the USB stick.
3. Network: Ethernet, or `nmtui` for Wi-Fi.
4. The console shows the IPv4 address and the `install-host` command line.

## New host

1. Add the host: a `den.hosts.<arch>.<host>` entry and `modules/den/hosts/<host>.nix`. Copy the shape of an existing host: `facter.reportPath = ./_facter/<host>.facter.json`, the disko import from `_hw/<host>/disko.nix`, `system.stateVersion`. Leave `sshHostKey` and `meshAddress` unset for now.
2. Generate the host key outside the repo, on a persisted path:
   ```bash
   nix run .#install-host -- keygen <host> ~/dev/<host>-keys
   ```
   It prints the age recipient and the `sshHostKey` value.
3. In `~/nix-secrets`:
   - add the recipient to `.sops.yaml` as `&<host>` and put `*<host>` on the creation rules for `hosts/<host>/` and `hosts/common/`;
   - create `hosts/<host>/secrets.yaml` (`nix run nixpkgs#sops -- hosts/<host>/secrets.yaml`);
   - `nix run nixpkgs#sops -- updatekeys hosts/<host>/secrets.yaml hosts/common/secrets.yaml`;
   - commit and push, then in nix-config: `nix flake lock --update-input nix-secrets`.
4. Install:
   ```bash
   nix run .#install-host -- install <host> <target-ip> --host-key ~/dev/<host>-keys/ssh_host_ed25519_key
   ```
   It refuses to start unless the target booted the cosmos installer and the **pinned** nix-secrets decrypts `hosts/<host>` and `hosts/common` with that key. A missing facter report is generated from the target first, and every run refreshes it. LUKS layouts prompt for the passphrase, and devices with `fido2-device=auto` in `crypttabExtraOpts` prompt for YubiKeys to enroll. Then the target reboots.
5. Work through the printed checklist: commit `modules/den/hosts/_facter/<host>.facter.json`, set the `sshHostKey` fact, enroll FIDO2 keys it skipped, set `resume_offset` if the host hibernates.
6. Enrol the host in NetBird with a setup key, then set its `meshAddress` fact.
7. Delete the key directory once the host runs: the key lives on the host in `/persist/etc/ssh` (`/etc/ssh` without impermanence).

Flags: `--port N` (installer SSH port, default 22), `--no-fido2`, `--no-reboot` (leave the target in the installer with `/mnt` mounted).

## Reinstall or move a host to new hardware

A host keeps its identity by keeping its SSH host key: take it from the old machine's `/persist/etc/ssh/ssh_host_ed25519_key` and pass it as `--host-key`. Nothing in nix-secrets changes.

To bring the data along, run `install-host` **on the machine being replaced** with `--copy-persist`: after installing, it streams this machine's `/persist` into the target's `/mnt/persist` (tar over SSH, owners, ACLs and xattrs preserved). `--exclude-from FILE` skips paths: one pattern per line, matched against the whole path `./<path under /persist>`, `*` crosses `/`, and no comment lines (tar would read them as patterns). With `--copy-persist` the target is not rebooted: power off the old machine first, so two machines never hold the same identity on the mesh, then on the target run `swapoff -a; umount -R /mnt; reboot`.

voyager's move to the Framework Laptop 12 is the worked example: [Moving voyager to the Framework 12](#moving-voyager-to-the-framework-12).

## Conventions

- LUKS layouts read the passphrase from `passwordFile = "/tmp/secret.key"`; install-host uploads it there.
- The facter report lives at `modules/den/hosts/_facter/<host>.facter.json`.
- Disko layouts live in `modules/den/hosts/_hw/<host>/`.

## Troubleshooting

- install-host runs the nixos-anywhere phases `disko,install` and builds locally (`--build-on local`), because only this machine can fetch nix-secrets.
- If the install fails after disko, rerun only the install phase from the same checkout, without repartitioning:
  ```bash
  nix run github:nix-community/nixos-anywhere -- --flake .#<host> --target-host root@<ip> \
    --build-on local --phases install --extra-files <dir with persist/etc/ssh/ssh_host_ed25519_key>
  ```
  Build the `--extra-files` tree the way install-host does: the key at the path from `sops.age.sshKeyPaths`, mode 0600.
- `nix eval .#nixosConfigurations.<host>.config.networking.hostName` failing before anything touches the disk usually means a missing `git add` of the new host file or facter report.

## Moving voyager to the Framework 12

voyager keeps its identity (host key, sops access, mesh address, data) and moves from the ThinkPad P1 to the Framework Laptop 12. Everything hardware-specific sits behind `hardwareProfile` in `modules/den/hosts/voyager.nix` (`_hw/voyager/thinkpad-p1.nix`, `_hw/voyager/framework-12.nix`), so the move is one word plus one `install-host` run.

1. **Firmware** (F2 at power-on): Secure Boot **off** (GRUB is unsigned); stylus protocol **MPP**, because USI mode has reports of a stuck eraser on Linux; BIOS ≥ 3.00. Fit the Ethernet expansion card and plug it in.
2. **Installer:** `nix build .#installer-iso`, `dd` it to a USB stick (see [Build the installer](#build-the-installer)) and boot the Framework from it. Note the IPv4 shown on the console.
3. **Flip the profile.** On the P1, in `~/nix-config`: `git pull`, set `hardwareProfile = "framework-12";` in `modules/den/hosts/voyager.nix`, commit (`feat(voyager): move to the Framework Laptop 12`) and push. Do **not** `nh os switch` the P1 onto this commit. Until the Framework's facter report replaces the P1's, this commit evaluates but does not build (the P1 report puts `nvidia` in the initrd, which the Framework kernel lacks) and build-gate stays red for voyager; install-host regenerates the report from the target before building, and step 6 commits it.
4. Close the browser, mail and IDE (their state is copied live). Then:
   ```bash
   sudo install -m 600 -o lvdar /persist/etc/ssh/ssh_host_ed25519_key ~/dev/voyager-hostkey
   sudo install -m 644 -o lvdar /persist/etc/ssh/ssh_host_ed25519_key.pub ~/dev/voyager-hostkey.pub
   nix run .#install-host -- install voyager <framework-ip> --host-key ~/dev/voyager-hostkey \
     --copy-persist --exclude-from modules/den/hosts/_hw/voyager/persist-exclude
   shred -u ~/dev/voyager-hostkey && rm ~/dev/voyager-hostkey.pub
   ```
   Enter the LUKS passphrase; it stays the fallback unlock. When prompted, plug each YubiKey into the **Framework** for FIDO2 enrolment. The copy is about 72 GiB (measured 2026-10-30 with the exclude list), roughly 15 minutes over gigabit Ethernet.
5. Power off the P1. On the Framework console run `swapoff -a; umount -R /mnt; reboot`, then remove the USB stick.
6. On the Framework: log in, `git -C ~/nix-config add modules/den/hosts/_facter/voyager.facter.json`, commit (`chore(voyager): framework 12 facter report`), push, then `nh os switch`.
7. Check:
   - [ ] boot unlocks with a YubiKey touch and with the passphrase;
   - [ ] `journalctl -b -u rollback` is clean;
   - [ ] `hostname` is voyager, and `sudo cat /run/secrets/keys/age >/dev/null` works (sops decrypts);
   - [ ] `netbird status` shows 100.68.60.163, and `ssh -p 2222 root@endeavour.nb.lvdar.nl true` works;
   - [ ] `nix eval .#nixosConfigurations.voyager.config.hardware.cpu.intel.updateMicrocode` is `true` (else add `hardware.cpu.intel.updateMicrocode = true;` to `framework-12.nix`);
   - [ ] folding the hinge: `libinput debug-events | grep -m1 tablet-mode` prints `switch tablet-mode state 1` and wvkbd appears (if the line format differs, adjust only the `case` patterns in `desktop/_umbriel/system.nix`);
   - [ ] rotating rotates the screen, and touch and stylus follow (if inverted: pass `--transform normal 270 180 90` mapping args to iio-niri's `extraArgs` in `desktop/tablet.nix` and swap 90/270 in `umbriel-autorotate`);
   - [ ] touch gestures follow the screen's rotation: in every orientation, swiping up from the bottom edge toggles the overview (`journalctl --user -u lisgd` for errors; if the directions are wrong, fix the `case` in `lisgd-niri` in `desktop/tablet.nix`);
   - [ ] the stylus shows pressure in Xournal++;
   - [ ] `systemctl hibernate` resumes (see [Hibernation](#hibernation));
   - [ ] `cat /etc/nix/machines` lists endeavour;
   - [ ] `df -h /` leaves at least 100 GB free.
8. **Cleanup commit**, once the Framework has run well for a week:
   - delete `_hw/voyager/thinkpad-p1.nix`, `aspects/hardware/thinkpad.nix` and `aspects/hardware/fingerprint.nix`;
   - delete the `cudaSupport` option in `home/apps/obs-studio.nix`;
   - delete the `thinkpadFan` option and its uses in `home/desktop/_noctalia/{home,plugins}.nix`, plus the thinkpad-fan `postPatch`;
   - delete the `hardwareProfile`/`profiles` selector, importing `framework-12.nix` directly;
   - reword the ThinkPad comment in `desktop/bluetooth.nix`;
   - update [Hosts](hosts.md#voyager).

   Then wipe the P1 (`blkdiscard` its NVMe), or reinstall it later as a new host with fresh keys.

### What the exclude list skips

`modules/den/hosts/_hw/voyager/persist-exclude` keeps the copy to what the Framework needs:

- the Steam library (`steamapps`): games re-download;
- build artifacts (`dev/*/target`, `dev/*/node_modules`, `dev/.Trash-1000`): they regenerate;
- orphans no aspect persists any more (`downloads`, `software`, `.mozilla`, `nixos-config`, `.local/share/{protonmail,lutris,FreeCAD,containers}`): if any of it matters, `rsync` it off the P1 over the mesh before wiping;
- leftovers of removed features: rofi and clipse (Hyprland), `/var/lib/fprint` (the Framework 12 has no fingerprint reader), `/var/cache/tuigreet`.

### Hibernation

Neither profile hard-codes `resume=`/`resume_offset=`: systemd writes the `HibernateLocation` EFI variable (device and swap-file offset) when it hibernates, and the systemd initrd resumes from it. If the Framework boots fresh after `systemctl hibernate` instead of resuming, add to `framework-12.nix`:

```nix
boot.resumeDevice = "/dev/mapper/crypted";
boot.kernelParams = ["resume_offset=<n>"]; # sudo btrfs inspect-internal map-swapfile -r /.swapvol/swapfile
```

install-host's checklist prints the `map-swapfile` command whenever `boot.resumeDevice` is set.
