{
  inputs,
  config,
  lib,
  ...
}: let
  inherit (lib.types) listOf str;
  inherit (lib.options) mkEnableOption mkOption;
  inherit (lib.modules) mkIf mkBefore;

  cfg = config.system.impermanence;
in {
  imports = [
    inputs.impermanence.nixosModules.impermanence
  ];

  options.system.impermanence = {
    enable = mkEnableOption "impermanence";

    device = mkOption {
      type = str;
      default = "/dev/mapper/crypted";
      description = "The device the root filesystem is located on";
    };

    persist = {
      files = mkOption {
        type = listOf str;
        default = [];
        description = "List of files to persist in /persist";
      };
      directories = mkOption {
        type = listOf str;
        default = [];
        description = "List of directories to persist in /persist";
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
  };
}
