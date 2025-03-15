{inputs, ...}: {
  imports = [
    ./hardware-configuration.nix
    (import ./disko.nix {device = "/dev/nvme0n1";})
    inputs.nixos-hardware.nixosModules.lenovo-thinkpad-p1-gen3
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

  environment.sessionVariables = {
    FLAKE = "/home/lvdar/nixos-config";
  };

  modules = {
    tuigreet.enable = true;
    hyprland.enable = true;
    networkmanager.enable = true;
    nh.enable = true;
    persist.enable = true;
    ssh.enable = true;
    sudo.enable = true;
    yubico.enable = false;
    zsh.enable = true;
  };

  nix.settings.experimental-features = ["nix-command" "flakes"];

  system.stateVersion = "24.11";
}
