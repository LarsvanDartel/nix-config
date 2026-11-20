# core.impermanence — root-on-btrfs impermanence: rolls root back to a blank snapshot each boot and bind-mounts persist paths from /persist.
{inputs, ...}: let
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

    persistedPaths = map (d:
      if builtins.isAttrs d
      then d.directory
      else d)
    cfg.persist.directories;

    rootDeviceUnit = "${utils.escapeSystemdPath cfg.device}.device";
  in {
    imports = [inputs.impermanence.nixosModules.impermanence];

    config = {
      cosmos.system.impermanence.active = true;

      home-manager.sharedModules = [homeImpermanence];

      boot.initrd.systemd.services.rollback = {
        description = "Roll back BTRFS root subvolume to a blank snapshot";
        wantedBy = ["initrd.target"];
        # Wait for the .device unit, not cryptsetup: hosts without LUKS (gaia) have no cryptsetup unit.
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
          # -t btrfs is load-bearing: the initrd has no blkid, and a failed mount here boots on without
          # wiping root (nothing orders after this unit), which looks exactly like a working rollback.
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
          # -mindepth 1 is load-bearing: without it old_roots/ matches itself after 30 days, and deleting it
          # fails after root was moved aside and before the new one exists, leaving nothing to boot.
          for i in $(find /btrfs_tmp/old_roots/ -mindepth 1 -maxdepth 1 -mtime +30); do
              delete_subvolumes_recursively "$i"
          done
          btrfs subvolume create /btrfs_tmp/root

          # Carry machine-id across the wipe: journald keys its storage on it, so a fresh one hides old logs.
          # Seeded here because impermanence `files` refuses to bind over the machine-id systemd created.
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

        # Never add /etc/machine-id to `files`: impermanence fails activation; the rollback script seeds it.

        directories =
          cfg.persist.directories
          ++ [
            "/var/log"
            "/var/lib/nixos"
            "/var/lib/systemd/coredump"
            # Lose this and every Persistent=true timer fires on next boot.
            "/var/lib/systemd/timers"
          ];
      };

      # The switch that first persists a directory mounts it over the subdirs tmpfiles just made; this recreates them.
      # Not wantedBy/before local-fs.target: services' implicit After=sysinit.target makes that a cycle.
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
