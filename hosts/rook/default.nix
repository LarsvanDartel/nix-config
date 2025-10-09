{inputs, ...}: {
  imports = [
    # Hardware
    ./hardware-configuration.nix
    inputs.nixos-hardware.nixosModules.common-cpu-intel-cpu-only
    inputs.nixos-hardware.nixosModules.common-gpu-nvidia-nonprime

    # Disk layout
    inputs.disko.nixosModules.disko
    ./disko.nix
  ];

  system = {
    impermanence = {
      enable = true;
      device = "/dev/disk/by-label/nixos";
    };
  };

  profiles = {
    server.enable = true;
  };

  hardware = {
    nvidia = {
      modesetting.enable = true;
      powerManagement.enable = true;
      open = false;
      nvidiaPersistenced = true;
      videoAcceleration = true;
    };
    # ipmi-fancontrol.enable = true;
  };

  system.stateVersion = "24.11";
}
