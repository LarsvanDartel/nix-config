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
    ...
  }: let
    inherit (lib.attrsets) mapAttrsToList filterAttrs;
    inherit (lib.strings) concatLines escapeShellArg;

    cfg = config.cosmos.system.impermanence;
  in {
    imports = [inputs.impermanence.nixosModules.impermanence];

    config = {
      cosmos.system.impermanence.active = true;

      home-manager.sharedModules = [homeImpermanence];

      boot.initrd.systemd.services.rollback = {
        description = "Roll back BTRFS root subvolume to a blank snapshot";
        wantedBy = ["initrd.target"];
        after = ["systemd-cryptsetup@${builtins.baseNameOf cfg.device}.service"];
        before = ["sysroot.mount"];
        unitConfig.DefaultDependencies = "no";
        serviceConfig = {
          Type = "oneshot";
          StandardOutput = "journal";
          StandardError = "journal";
        };
        script = ''
          mkdir -p /btrfs_tmp
          mount -o subvol=/ ${cfg.device} /btrfs_tmp
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
          for i in $(find /btrfs_tmp/old_roots/ -maxdepth 1 -mtime +30); do
              delete_subvolumes_recursively "$i"
          done
          btrfs subvolume create /btrfs_tmp/root
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
