{
  inputs,
  config,
  lib,
  ...
}: let
  inherit (lib.types) listOf str coercedTo attrsOf;
  inherit (lib.options) mkEnableOption mkOption;
  inherit (lib.modules) mkIf mkBefore;
  inherit (lib.attrsets) mapAttrsToList filterAttrs;
  inherit (lib.strings) concatLines escapeShellArg;

  cfg = config.cosmos.system.impermanence;
in {
  imports = [
    inputs.impermanence.nixosModules.impermanence
  ];

  options.cosmos.system.impermanence = {
    enable = mkEnableOption "impermanence";

    device = mkOption {
      type = str;
      default = "/dev/mapper/crypted";
      description = "The device the root filesystem is located on";
    };

    persist = {
      files = mkOption {
        type = listOf (coercedTo str (f: {file = f;}) (attrsOf str));
        default = [];
        example = [
          "/etc/machine-id"
          "/etc/nix/id_rsa"
        ];
        description = ''
          Files that should be stored in persistent storage.
        '';
      };
      directories = mkOption {
        type = listOf (coercedTo str (d: {directory = d;}) (attrsOf str));
        default = [];
        example = [
          "/var/log"
          "/var/lib/bluetooth"
          "/var/lib/nixos"
          "/var/lib/systemd/coredump"
          "/etc/NetworkManager/system-connections"
        ];
        description = ''
          Directories to bind mount to persistent storage.
        '';
      };
    };
  };

  config = mkIf cfg.enable {
    boot.initrd.postDeviceCommands = mkBefore ''
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
}
