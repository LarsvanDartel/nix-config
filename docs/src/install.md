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
