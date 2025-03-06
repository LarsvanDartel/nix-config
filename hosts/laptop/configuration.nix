{
  config,
  lib,
  pkgs,
  inputs,
  ...
}: {
  imports = [
    ./hardware-configuration.nix
    (import ./disko.nix {device = "/dev/nvme0n1";})
  ];

  boot.loader = {
    efi = {
      canTouchEfiVariables = true;
      efiSysMountPoint = "/boot";
    };
    grub = {
      devices = ["nodev"];
      efiSupport = true;
      enable = true;
      useOSProber = true;
    };
  };

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
          delete_subvolume_recursively "/btrfs_tmp/$i"
        done
        btrfs subvolume delete "$1"
    }

    for i in $(find /btrfs_tmp/old_roots/ -maxdepth 1 -mtime +30); do
        delete_subvolumes_recursively "$i"
    done

    btrfs subvolume create /btrfs_tmp/root
    umount /btrfs_tmp
  '';

  # TODO: Make dependent on users config
  # systemd.tmpfiles.rules = [
  #   "d /persist/home/ 1777 root root -"
  #   "d /persist/home/lvdar 0770 lvdar users -"
  # ];

  programs.fuse.userAllowOther = true;
  fileSystems."/persist".neededForBoot = true;
  environment.persistence."/persist/system" = {
    hideMounts = true;
    directories = [
      "/var/log"
      "/var/lib/nixos"
      "/var/lib/systemd/coredump"
    ];
  };

  networking.hostName = "S20212041";

  nix.settings.experimental-features = ["nix-command" "flakes"];

  system.stateVersion = "24.11";
}
