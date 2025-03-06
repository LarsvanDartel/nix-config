{
  config,
  lib,
  pkgs,
  inputs,
  ...
}: {
  imports = [
    ./hardware-configuration.nix

    inputs.disko.nixosModules.default
    (import ./disko.nix {device = "/dev/nvme0n1";})

    inputs.impermanence.nixosModules.impermanence
    inputs.home-manager.nixosModules.default
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

  systemd.tmpfiles.rules = [
    "d /persist/home/ 1777 root root -"
    "d /presist/home/lvdar 0770 lvdar users -"
  ];

  fileSystems."/persist".neededForBoot = true;
  environment.persistence."/persist/system" = {
    hideMounts = true;
    directories = [
      "/var/log"
      "/var/lib/nixos"
      "/var/lib/systemd/coredump"
    ];
  };

  networking.hostName = "S20212041"; # Define your hostname.
  # networking.wireless.enable = true; # Enables wireless support via wpa_supplicant.

  nix.settings.experimental-features = ["nix-command" "flakes"];

  # Set your time zone.
  time.timeZone = "Europe/Amsterdam";

  # Select internationalisation properties.
  i18n.defaultLocale = "en_US.UTF-8";
  console = {
    font = "Lat2-Terminus16";
    earlySetup = true; # Switch keymap for Nixos stage 1
    useXkbConfig = true; # use xkb.options in tty.
  };

  # Enable the X11 windowing system.
  # services.xserver.enable = true;

  # Configure keymap in X11
  services.xserver.xkb.layout = "us";
  services.xserver.xkb.variant = "dvp";
  services.xserver.xkb.options = "caps:escape";

  # Add users
  users.users.lvdar = {
    isNormalUser = true;
    extraGroups = ["wheel"]; # Enable ‘sudo’ for the user.
    initialPassword = "pwd";
    packages = with pkgs; [
      neovim
    ];
  };

  programs.fuse.userAllowOther = true;
  home-manager = {
    extraSpecialArgs = {inherit inputs;};
    users = {
      "lvdar" = import ./home.nix;
    };
  };

  nixpkgs.config.allowUnfree = true;

  system.stateVersion = "24.11";
}
