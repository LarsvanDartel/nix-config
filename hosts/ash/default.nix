{
  inputs,
  config,
  ...
}: {
  imports = [
    # Hardware
    ./hardware-configuration.nix
    inputs.nixos-hardware.nixosModules.lenovo-thinkpad-p1-gen3

    # Disk layout
    inputs.disko.nixosModules.disko
    (import ./disko.nix {device = "/dev/nvme0n1";})
  ];

  boot = {
    kernelParams = [
      "resume_offset=533760"
    ];
    resumeDevice = "/dev/disk/by-uuid/c2dc9bb7-f815-4c9c-bd96-68bebb100aef";
  };

  system.impermanence.enable = true;

  profiles = {
    desktop = {
      enable = true;
      addons = {
        hyprland.enable = true;
        greetd.tuigreet.enable = true;
      };
    };
  };

  hardware.fingerprint.enable = true;

  cli.programs.nh = {
    flake-dir = "/home/${config.user.name}/nix-config";
  };

  system.stateVersion = "24.11";
}
