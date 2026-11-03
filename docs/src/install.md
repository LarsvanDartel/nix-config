# Installing a host

Installs run from a fleet machine with nix-secrets access (voyager) against a target booted from the cosmos installer ISO. `install-host` wraps [nixos-anywhere](https://github.com/nix-community/nixos-anywhere): it partitions with the host's disko layout, installs the closure built locally, and places the host's SSH key, which is also its sops identity, before first boot.

## Build the installer

```bash
nix build .#installer-iso
sudo dd if=result/iso/*.iso of=/dev/sdX bs=4M conv=fsync status=progress
```

The ISO is the NixOS minimal installer with the latest kernel and no ZFS, plus `nixos-facter`, `git` and `pv`. Root is reachable over SSH with the keys in `modules/den/aspects/core/_ssh-keys/authorized.nix` (the device key and the YubiKeys). It carries no secrets and no NetBird: reach it over the LAN.

## Prepare the target

1. Firmware: Secure Boot **off** (the installer is unsigned).
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
   It refuses to start unless the target booted the cosmos installer and the **pinned** nix-secrets decrypts `hosts/<host>` and `hosts/common` with that key. A missing facter report is generated from the target first, and every run refreshes it. LUKS layouts prompt for the passphrase, and devices with `fido2-device=auto` in `crypttabExtraOpts` prompt for YubiKeys to enroll, touch only (no PIN: a folded convertible has no keyboard to type it on). Then the target reboots.
5. Work through the printed checklist: commit `modules/den/hosts/_facter/<host>.facter.json`, set the `sshHostKey` fact, enroll FIDO2 keys it skipped, set `resume_offset` if the host hibernates.
6. Enrol the host in NetBird with a setup key, then set its `meshAddress` fact.
7. Delete the key directory once the host runs: the key lives on the host in `/persist/etc/ssh` (`/etc/ssh` without impermanence).

Flags: `--port N` (installer SSH port, default 22), `--no-fido2`, `--no-reboot` (leave the target in the installer with `/mnt` mounted).

## Reinstall or move a host to new hardware

A host keeps its identity by keeping its SSH host key: take it from the old machine's `/persist/etc/ssh/ssh_host_ed25519_key` and pass it as `--host-key`. Nothing in nix-secrets changes.

To bring the data along, run `install-host` **on the machine being replaced** with `--copy-persist`: after installing, it streams this machine's `/persist` into the target's `/mnt/persist` (tar over SSH, owners, ACLs and xattrs preserved). `--exclude-from FILE` skips paths: one pattern per line, matched against the whole path `./<path under /persist>`, `*` crosses `/`, and no comment lines (tar would read them as patterns). With `--copy-persist` the target is not rebooted: power off the old machine first, so two machines never hold the same identity on the mesh, then on the target run `swapoff -a; umount -R /mnt; reboot`.

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

## Hibernation

voyager hard-codes no `resume=`/`resume_offset=`: systemd writes the `HibernateLocation` EFI variable (device and swap-file offset) when it hibernates, and the systemd initrd resumes from it. If voyager boots fresh after `systemctl hibernate` instead of resuming, add to `_hw/voyager/framework-12.nix`:

```nix
boot.resumeDevice = "/dev/mapper/crypted";
boot.kernelParams = ["resume_offset=<n>"]; # sudo btrfs inspect-internal map-swapfile -r /.swapvol/swapfile
```

install-host's checklist prints the `map-swapfile` command whenever `boot.resumeDevice` is set.

## Firmware updates

Framework publishes the Laptop 12's BIOS, a bundle that also carries the EC, PD and CSME firmware, to [LVFS](https://fwupd.org). voyager's hardware module (`_hw/voyager/framework-12.nix`) gets fwupd from nixos-hardware, and persists `/var/lib/fwupd`, where fwupd records a staged update and checks its result after the reboot. Update from the installed system, plugged in to a charger:

```bash
fwupdmgr refresh --force
fwupdmgr get-updates
fwupdmgr update        # stages a UEFI capsule on the ESP and asks to reboot
```

The firmware flashes during the reboot (progress bar; don't interrupt it), then boots voyager again. `fwupdmgr get-history` shows the result. Under [Secure Boot](#secure-boot) the same works: lanzaboote signs fwupd's EFI helper with the host's key.

You don't have to look: `core.firmware-updates` (in every host's baseline, active wherever fwupd is on) runs after each hourly `fwupd-refresh` and pushes "voyager: firmware update available" with the installed and offered versions to the `fleet` ntfy topic, once per new version. `systemctl start fwupd-refresh` checks right away; `journalctl -u firmware-updates` shows what it saw.

Releases and notes: [Framework Laptop 12 Intel Core Series 3 — BIOS & Drivers](https://resources.frame.work/downloads/laptop-12/intel-core-series-3/). Without a working system, the *EFI Shell Update* zip from that page, extracted to a FAT32 stick and booted with F12, flashes it too.

## Secure Boot

`cosmos.system.boot.secureBoot` (`core.boot`) replaces GRUB with [lanzaboote](https://github.com/nix-community/lanzaboote): systemd-boot booting images signed with the host's own keys. On the first boot or switch with it, `generate-sb-keys` creates the keys in `/var/lib/sbctl` (persisted) and `prepare-sb-auto-enroll` puts their enrolment files in `/boot/loader/keys/auto`. systemd-boot enrolls them the next time it starts with the firmware in setup mode. genix gets a signed UKI at `/boot/EFI/Linux/genix.efi` (unit `genix-uki`), and the `genix` command sets `bootctl set-oneshot genix.efi`. voyager's hardware module also enrolls the firmware's built-in keys, Framework's db and KEK, next to Microsoft's: Framework's own EFI tools are signed with them.

Turning it on for voyager:

1. Add `cosmos.system.boot.secureBoot = true;` to voyager's `nixos` block, commit (`feat(voyager): enable secure boot`), push, and `nh os switch`. The switch installs systemd-boot unsigned, then creates the keys, signs everything and writes the enrolment files. Check:
   - `sudo sbctl verify` lists the files under `/boot/EFI` as signed, except lanzaboote's `kernel-*` files, which the signed stubs check by hash;
   - `sudo ls /boot/loader/keys/auto` shows `PK.auth KEK.auth db.auth`.
2. Boot systemd-boot. lzbt never creates a firmware boot entry, and the firmware's GRUB entry would keep booting GRUB's last, now frozen, menu:
   ```bash
   sudo efibootmgr --create --disk /dev/nvme0n1 --part 1 --label "Linux Boot Manager" --loader '\EFI\systemd\systemd-bootx64.efi'
   systemctl reboot
   ```
   systemd-boot's menu shows NixOS and genix; `bootctl status` reports systemd-boot. Only then retire GRUB: `sudo efibootmgr` to find the `NixOS-boot` entry, `sudo efibootmgr --bootnum <n> --delete-bootnum`, and `sudo rm -rf /boot/EFI/NixOS-boot /boot/grub /boot/kernels /boot/genix`.
3. Firmware: `systemctl reboot --firmware-setup`. Set an administrator password (without one, anyone can switch Secure Boot off again). Under *Security → Secure Boot*, choose *Erase all Secure Boot Settings*, which puts the firmware in setup mode, keep Secure Boot enabled, save and exit. systemd-boot enrolls the keys after a short countdown (don't press a key) and reboots.
4. Check:
   - [ ] `sudo sbctl status`: Secure Boot enabled, Setup Mode disabled;
   - [ ] NixOS and `genix` each boot;
   - [ ] LUKS unlocks with a YubiKey touch and with the passphrase;
   - [ ] `systemctl hibernate` still resumes;
   - [ ] `fwupdmgr get-devices` lists the system firmware (BIOS updates need Framework's keys, enrolled above).

Reinstalling a host with Secure Boot on: the installer is unsigned, so switch Secure Boot off for install-host. The fresh install generates new keys unless `--copy-persist` brings `/persist/var/lib/sbctl` along. With new keys, erase the firmware's keys again (step 3); with the copied keys, just switch Secure Boot back on.
