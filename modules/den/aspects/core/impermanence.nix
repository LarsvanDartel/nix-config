# Root-on-btrfs impermanence (was flake.modules.nixos.impermanence): rolls the
# root subvolume back to a blank snapshot each boot and bind-mounts everything
# under cosmos.system.impermanence.persist.* from /persist. Opt-in per host (only
# hosts with a btrfs root + /persist), so NOT in roles.default. The home side is
# pushed to every user via home-manager.sharedModules, matching the legacy
# feature; the impermanence nixos module auto-injects the HM impermanence module
# (home.persistence option).
{inputs, ...}: let
  # Home persistence activation + its option schema (home-relative persist paths).
  # Self-contained so it works as a sharedModule regardless of the home baseline.
  homeImpermanence = {
    config,
    lib,
    ...
  }: let
    inherit (lib.types) listOf str coercedTo attrsOf bool;
    inherit (lib.options) mkOption;
  in {
    options.cosmos.system.impermanence = {
      active = mkOption {
        type = bool;
        default = false;
        internal = true;
      };
      persist = {
        files = mkOption {
          type = listOf (coercedTo str (f: {file = f;}) (attrsOf str));
          default = [];
        };
        directories = mkOption {
          type = listOf (coercedTo str (d: {directory = d;}) (attrsOf str));
          default = [];
        };
      };
    };

    config = {
      cosmos.system.impermanence.active = true;
      home.persistence."/persist" = {
        inherit (config.cosmos.system.impermanence.persist) files directories;
      };
    };
  };
in {
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
        inherit (cfg.persist) files;
        hideMounts = true;
        directories =
          cfg.persist.directories
          ++ [
            "/var/log"
            "/var/lib/nixos"
            "/var/lib/systemd/coredump"
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
