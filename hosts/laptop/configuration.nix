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
    (import ./disko.nix {device = "/dev/nvme1n1";})

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

  home-manager = {
    extraSpecialArgs = {inherit inputs;};
    users = {
      "lvdar" = import ./home.nix;
    };
  };

  nixpkgs.config.allowUnfree = true;

  system.stateVersion = "24.11";
}
