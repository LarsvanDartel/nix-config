# Root-on-btrfs impermanence: rolls the root subvolume back to a blank snapshot
# each boot and bind-mounts cosmos.system.impermanence.persist.* from /persist.
# Opt-in per host (btrfs root + /persist required), so NOT in roles.default.
# The home side reaches every user via home-manager.sharedModules; the nixos
# module auto-injects the HM impermanence module (home.persistence option).
{inputs, ...}: let
  # Option schema is declared by impermanence-options (present on every
  # host); here we only set values.
  homeImpermanence = {config, ...}: {
    cosmos.system.impermanence.active = true;
    home.persistence."/persist" = {
      inherit (config.cosmos.system.impermanence.persist) files directories;
    };
  };
in {
  flake-file.inputs.impermanence.url = "github:nix-community/impermanence";

  den.aspects.core.impermanence.nixos = {
    config,
    lib,
    utils,
    ...
  }: let
    inherit (lib.attrsets) mapAttrsToList filterAttrs;
    inherit (lib.strings) concatLines escapeShellArg;

    cfg = config.cosmos.system.impermanence;

    # persist.directories takes a bare path or an attrset with ownership.
    persistedPaths = map (d:
      if builtins.isAttrs d
      then d.directory
      else d)
    cfg.persist.directories;

    # The systemd .device unit for the root device. escapeSystemdPath lives in
    # NixOS's `utils`, not in lib.
    rootDeviceUnit = "${utils.escapeSystemdPath cfg.device}.device";
  in {
    imports = [inputs.impermanence.nixosModules.impermanence];

    config = {
      cosmos.system.impermanence.active = true;

      home-manager.sharedModules = [homeImpermanence];

      boot.initrd.systemd.services.rollback = {
        description = "Roll back BTRFS root subvolume to a blank snapshot";
        wantedBy = ["initrd.target"];
        # Wait for the .device unit, not merely for cryptsetup: on gaia (plain
        # partition, no LUKS) the cryptsetup unit doesn't exist and the script
        # raced udev, failing with "special device /dev/disk/by-label/nixos
        # does not exist". The .device unit covers both shapes.
        after = [
          "systemd-cryptsetup@${builtins.baseNameOf cfg.device}.service"
          rootDeviceUnit
        ];
        requires = [rootDeviceUnit];
        before = ["sysroot.mount"];
        unitConfig.DefaultDependencies = "no";
        serviceConfig = {
          Type = "oneshot";
          StandardOutput = "journal";
          StandardError = "journal";
        };
        script = ''
          mkdir -p /btrfs_tmp
          # -t btrfs is load-bearing. Without it the initrd cannot probe the
          # type (no blkid in this environment), the mount fails, and because
          # DefaultDependencies=no means nothing orders itself after this unit,
          # the boot carries on happily *without* wiping the root subvolume.
          # This silently disabled impermanence on every host in the fleet
          # between March and August 2026: a machine that fails to wipe itself
          # looks exactly like one that works.
          mount -t btrfs -o subvol=/ ${cfg.device} /btrfs_tmp
          if [[ -e /btrfs_tmp/root ]]; then
              mkdir -p /btrfs_tmp/old_roots
              timestamp=$(date --date="@$(stat -c %Y /btrfs_tmp/root)" "+%Y-%m-%d_%H:%M:%S")
              mv /btrfs_tmp/root "/btrfs_tmp/old_roots/$timestamp"
          fi
          delete_subvolumes_recursively() {
              IFS=$'\n'
              for i in $(btrfs subvolume list -o "$1" | cut -f 9- -d ' '); do
                delete_subvolumes_recursively "/btrfs_tmp/$i"
              done
              btrfs subvolume delete "$1"
          }
          # -mindepth 1 is equally load-bearing: find reports its own starting
          # point at depth 0, so without it a stale old_roots/ matches itself
          # once its own mtime passes 30 days. The recursion would then delete
          # every old root and finally call `btrfs subvolume delete` on
          # old_roots/, which is a plain directory — that fails, and it fails
          # *after* root has been moved aside and *before* the replacement is
          # created, leaving nothing for sysroot.mount to find.
          #
          # Harmless while this ran every boot, because each boot refreshed
          # old_roots' mtime. Repairing the mount above without also fixing
          # this would have turned the first successful rollback into an
          # unbootable machine on precisely the hosts that needed it most.
          for i in $(find /btrfs_tmp/old_roots/ -mindepth 1 -maxdepth 1 -mtime +30); do
              delete_subvolumes_recursively "$i"
          done
          btrfs subvolume create /btrfs_tmp/root

          # Carry the machine identity across the wipe. systemd generates a
          # fresh machine-id when /etc/machine-id is missing, and journald keys
          # its storage on it — so without this every boot would start a new
          # /var/log/journal/<id>/, leaving the previous logs on the persisted
          # disk but invisible to journalctl, forever.
          #
          # Seeded here rather than through impermanence's `files`, which
          # refuses to bind-mount over the machine-id systemd has already
          # created and fails activation outright. persist is a top-level
          # subvolume, so it is readable from here without a second mount.
          if [[ -f /btrfs_tmp/persist/etc/machine-id ]]; then
              mkdir -p /btrfs_tmp/root/etc
              cp /btrfs_tmp/persist/etc/machine-id /btrfs_tmp/root/etc/machine-id
          fi

          umount /btrfs_tmp
        '';
      };

      programs.fuse.userAllowOther = true;

      fileSystems."/persist".neededForBoot = true;
      environment.persistence."/persist" = {
        hideMounts = true;

        inherit (cfg.persist) files;

        # /etc/machine-id is deliberately NOT in `files`: impermanence's
        # mount-file bails ("A file already exists at /etc/machine-id!") and
        # fails activation; pre-creating the bind mount leaves the unit failing
        # every boot. It is seeded in the rollback script instead — see above.

        directories =
          cfg.persist.directories
          ++ [
            "/var/log"
            "/var/lib/nixos"
            "/var/lib/systemd/coredump"
            # systemd's record of when each Persistent=true timer last ran;
            # lose it and every such timer fires immediately on the next boot
            # (here: a full restic backup + GC competing with boot itself).
            "/var/lib/systemd/timers"
          ];
      };

      # Re-create tmpfiles entries once the persist bind mounts are up.
      # NixOS activation runs `systemd-tmpfiles --create` before starting
      # units, so the switch that *first* persists a directory creates its
      # subdirs on the root subvolume and the bind mount then covers them with
      # the empty /persist copy (kavita and paperless died to this on
      # 2026-08-30; a reboot hides it — at boot the mounts precede
      # systemd-tmpfiles-setup, so it only bites on first deploy).
      # RequiresMountsFor orders this after every persist mount and re-triggers
      # whenever the persisted set changes.
      # Do NOT replace this ordering with wantedBy + before local-fs.target:
      # services get an implicit After=sysinit.target, which is already after
      # local-fs.target — a cycle. systemd refused the transaction on endeavour
      # ("Transaction order is cyclic", 2026-08-30).
      systemd.services.impermanence-tmpfiles = {
        description = "Re-create tmpfiles entries under the persisted mounts";
        wantedBy = ["sysinit.target"];
        after = ["local-fs.target"];
        before = ["sysinit.target" "shutdown.target"];
        conflicts = ["shutdown.target"];
        unitConfig = {
          DefaultDependencies = "no";
          RequiresMountsFor = persistedPaths;
        };
        serviceConfig = {
          Type = "oneshot";
          RemainAfterExit = true;
          ExecStart = "${config.systemd.package}/bin/systemd-tmpfiles --create";
          StandardOutput = "journal";
          StandardError = "journal";
        };
      };

      systemd.services."persist-home-create-root-paths" = let
        persistentHomesRoot = "/persist";
        listOfCommands =
          mapAttrsToList
          (
            _: user: let
              userHome = escapeShellArg (persistentHomesRoot + user.home);
            in ''
              if [[ ! -d ${userHome} ]]; then
                  echo "Persistent home root folder '${userHome}' not found, creating..."
                  mkdir -p --mode=${user.homeMode} ${userHome}
                  chown ${user.name}:${user.group} ${userHome}
              fi
            ''
          )
          (filterAttrs (_: user: user.createHome) config.users.users);
        stringOfCommands = concatLines listOfCommands;
      in {
        script = stringOfCommands;
        unitConfig = {
          Description = "Ensure users' home folders exist in the persistent filesystem";
          PartOf = ["local-fs.target"];
          After = ["persist-home.mount"];
        };
        serviceConfig = {
          Type = "oneshot";
          StandardOutput = "journal";
          StandardError = "journal";
        };
        wantedBy = ["local-fs.target"];
      };
    };
  };
}
