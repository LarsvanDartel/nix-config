{config, ...}: let
  nixos = config.flake.modules.nixos;
in {
  configurations.gaia = {
    system = "x86_64-linux";
    module = {inputs, ...}: let
      # Use a nixos-facter report if present, otherwise the committed
      # hardware-configuration.nix. Generate: nixos-facter -o modules/hosts/gaia/_hw/gaia.facter.json
      hardware =
        if builtins.pathExists ./_hw/gaia.facter.json
        then [
          inputs.nixos-facter-modules.nixosModules.facter
          {facter.reportPath = ./_hw/gaia.facter.json;}
        ]
        else [./_hw/hardware-configuration.nix];
    in {
      imports =
        (with nixos; [
          common
          server
          impermanence
          pangolin
          typstnique
        ])
        ++ hardware
        ++ [
          inputs.nixos-hardware.nixosModules.common-cpu-intel
          inputs.disko.nixosModules.disko
          ./_hw/disko.nix
        ];

      cosmos.system = {
        boot = {
          legacy = true;
          grub-device = "/dev/sda";
        };
        impermanence.device = "/dev/disk/by-label/nixos";
      };

      system.stateVersion = "24.11";
    };
  };
}
