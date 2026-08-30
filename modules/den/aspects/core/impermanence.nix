# Root-on-btrfs impermanence (was flake.modules.nixos.impermanence): rolls the
# root subvolume back to a blank snapshot each boot and bind-mounts everything
# under cosmos.system.impermanence.persist.* from /persist. Opt-in per host (only
# hosts with a btrfs root + /persist), so NOT in roles.default. The home side is
# pushed to every user via home-manager.sharedModules, matching the legacy
# feature; the impermanence nixos module auto-injects the HM impermanence module
# (home.persistence option).
{inputs, ...}: let
  # Home persistence activation. The cosmos.system.impermanence option schema is
  # declared by home.core (in every user's baseline); here we only set values.
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

    # persist.directories takes either a bare path or an attrset carrying
    # ownership, so both shapes have to be reduced to the path.
    persistedPaths = map (d:
      if builtins.isAttrs d
      then d.directory
      else d)
    cfg.persist.directories;

    # The systemd .device unit for the root device, e.g.
    # dev-disk-by\x2dlabel-nixos.device. escapeSystemdPath lives in NixOS's
    # `utils`, not in lib.
    rootDeviceUnit = "${utils.escapeSystemdPath cfg.device}.device";
  in {
    imports = [inputs.impermanence.nixosModules.impermanence];

    config = {
      cosmos.system.impermanence.active = true;

      home-manager.sharedModules = [homeImpermanence];

      boot.initrd.systemd.services.rollback = {
        description = "Roll back BTRFS root subvolume to a blank snapshot";
        wantedBy = ["initrd.target"];
        # Wait for the device to actually exist, not merely for cryptsetup to
        # have run. The cryptsetup ordering alone is enough on a LUKS host,
        # where the mapper node appears with the service — but it names a unit
        # that does not exist at all on gaia, whose root is a plain partition.
        # There the script raced udev and lost:
        #
        #   mount: /btrfs_tmp: special device /dev/disk/by-label/nixos does not
        #   exist.
        #
        # which is the *second* failure this unit produced, uncovered only once
        # `-t btrfs` let it get far enough to try. Requiring the .device unit
        # covers both shapes: a by-label symlink appears when udev settles, a
        # mapper node when cryptsetup opens it.
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

        # NOTE — a prerequisite for repairing the initrd rollback above.
        # /etc/machine-id is deliberately NOT persisted here, and has to be
        # before that repair lands.
        #
        # Once the rollback works, systemd gets a blank machine-id every boot
        # and generates a fresh one. journald keys its storage on that id, so
        # every boot would start a new /var/log/journal/<id>/: the old logs stay
        # on the persisted disk forever while journalctl stops being able to see
        # them. The machine looks like it has no history and quietly fills up.
        #
        # Adding it to `files` is the trap, and it was tried: impermanence's
        # mount-file bails with "A file already exists at /etc/machine-id!" and
        # exits 1, which fails activation outright. The module assumes a rollback
        # has already emptied /etc, and on these hosts that has never once
        # happened — so machine-id is a real file on the root subvolume.
        # Pre-creating the bind mount by hand gets activation through, but leaves
        # the same unit failing on every subsequent boot.
        #
        # The fix belongs in the rollback script itself: seed machine-id from
        # /persist into the freshly created subvolume before sysroot is mounted.
        # That is the same script that needs `-t btrfs`, so both land together
        # under a deliberate reboot rather than separately.

        directories =
          cfg.persist.directories
          ++ [
            "/var/log"
            "/var/lib/nixos"
            "/var/lib/systemd/coredump"
            # Where systemd records when each Persistent=true timer last ran.
            # Lose it and every such timer treats the next boot as a missed
            # run and fires immediately — which for this fleet means a reboot
            # kicks off a full restic backup and a GC at once, competing with
            # the boot it is already in the middle of.
            "/var/lib/systemd/timers"
          ];
      };

      # Re-create tmpfiles entries once the persist bind mounts are up.
      #
      # NixOS activation runs `systemd-tmpfiles --create` before it starts
      # units, and an impermanence bind mount is a unit. So on the switch that
      # *first* persists a directory, tmpfiles creates that directory's
      # subdirectories on the root subvolume, and the bind mount then covers
      # them with the empty copy from /persist. Anything the service expected
      # to find is gone — not missing permissions, missing directory.
      #
      # It cost two services on 2026-08-30. kavita died on
      #   install: cannot create '/var/lib/kavita/config/appsettings.json'
      # and paperless on
      #   FileNotFoundError: '/var/lib/paperless/index'
      # both of which are tmpfiles rules their own modules declare. A reboot
      # would have hidden it, because at boot the mounts are established before
      # systemd-tmpfiles-setup runs — which is exactly what makes this worth a
      # unit rather than a note: it only ever bites on first deploy, so it is
      # never fresh in anyone's mind when it does.
      #
      # RequiresMountsFor is what makes this correct rather than hopeful: it
      # orders this after every persist mount, and it changes whenever the
      # persisted set changes, so a switch that adds a directory restarts this
      # unit instead of leaving a stale success behind. Ordering it before
      # local-fs.target puts it ahead of the services that will want those
      # directories.
      #
      # The ordering is systemd-tmpfiles-setup.service's own, deliberately:
      # after local-fs.target, before sysinit.target, DefaultDependencies off.
      # The obvious shape — wantedBy + before local-fs.target — is a cycle, and
      # it took endeavour's switch down on 2026-08-30 with
      #
      #   Failed to start sysinit.target: Transaction order is cyclic.
      #
      # because a service gets an implicit After=sysinit.target, sysinit.target
      # is already ordered after local-fs.target, and Before=local-fs.target
      # closes the loop. systemd refuses such a transaction at runtime, which
      # is the loud failure; at boot it instead breaks the cycle by dropping an
      # edge it picks itself, which is the quiet one.
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
