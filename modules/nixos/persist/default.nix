{
  config,
  lib,
  ...
}: let
  cfg = config.modules.persist;
in {
  options.modules.persist = {
    enable = lib.mkEnableOption "impermanence";
    directories = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [];
      description = "Directories to keep on boot";
    };
    files = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [];
      description = "Files to keep on boot";
    };
  };

  config = lib.mkIf cfg.enable {
    boot.initrd.postDeviceCommands = lib.mkBefore ''
      mkdir -p /btrfs_tmp

      mount -o subvol=/ /dev/mapper/crypted /btrfs_tmp

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
    environment.persistence."/persist/system" = {
      inherit (cfg) files;
      hideMounts = true;
      directories =
        cfg.directories
        ++ [
          "/var/log"
          "/var/lib/nixos"
          "/var/lib/systemd/coredump"
        ];
    };
  };
}
