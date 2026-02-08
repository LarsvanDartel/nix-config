{inputs, ...}: {
  imports = [
    # Hardware
    ./hardware-configuration.nix
    inputs.nixos-hardware.nixosModules.common-cpu-intel

    # Disk layout
    inputs.disko.nixosModules.disko
    ./disko.nix
  ];

  config = {
    cosmos = {
      system = {
        boot = {
          legacy = true;
          grub-device = "/dev/sda";
        };
        impermanence = {
          enable = true;
          device = "/dev/disk/by-label/nixos";
        };
      };

      profiles = {
        server.enable = true;
      };
    };

    system.stateVersion = "24.11";
  };
}
