{
  inputs,
  pkgs,
  ...
}: {
  imports = [
    ./hardware-configuration.nix
    (import ./disko.nix {device = "/dev/nvme0n1";})
    inputs.nixos-hardware.nixosModules.lenovo-thinkpad-p1-gen3
  ];

  boot = {
    loader = {
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

    kernelParams = [
      "resume_offset=533760"
    ];

    resumeDevice = "/dev/disk/by-uuid/c2dc9bb7-f815-4c9c-bd96-68bebb100aef";
  };

  environment.sessionVariables = {
    FLAKE = "/home/lvdar/nixos-config";
  };
  environment.shells = with pkgs; [zsh];

  modules = {
    bluetooth.enable = true;
    firewall.enable = true;
    tuigreet.enable = true;
    hyprland.enable = true;
    networkmanager.enable = true;
    nh.enable = true;
    persist.enable = true;
    ssh.enable = true;
    sudo.enable = true;
    unfree.enable = true;
    virt-manager.enable = true;
    yubico.enable = false;
    zsh.enable = true;
  };

  nix.settings.experimental-features = ["nix-command" "flakes"];

  system.stateVersion = "24.11";
}
