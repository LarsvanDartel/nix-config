{
  inputs,
  config,
  lib,
  pkgs,
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

  # Hibernate
  boot = {
    kernelParams = [
      "resume_offset=533760"
    ];
    resumeDevice = "/dev/disk/by-uuid/c2dc9bb7-f815-4c9c-bd96-68bebb100aef";
  };

  hardware.graphics.extraPackages = lib.mkForce (with pkgs; [
    intel-vaapi-driver # VA-API driver for older Intel GPUs
    intel-media-driver # VA-API driver for newer Intel GPUs (Broadwell+)
    vpl-gpu-rt # Intel Video Processing Library
    # NOT including:
    # intel-compute-runtime (depends on intel-graphics-compiler - broken)
    # intel-ocl (also OpenCL related)
  ]);

  profiles = {
    desktop = {
      enable = true;
      addons = {
        hyprland.enable = true;
        greetd.tuigreet.enable = true;
      };
    };
    gaming.enable = true;
  };

  system = {
    impermanence = {
      enable = true;
      device = "/dev/mapper/crypted";
    };

    boot.detect-windows = true;

    stateVersion = "24.11";
  };

  hardware.fingerprint.enable = true;

  cli.programs.nh = {
    flake-dir = "/home/${config.user.name}/nix-config";
  };
}
