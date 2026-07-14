{config, ...}: let
  nixos = config.flake.modules.nixos;
in {
  configurations.pioneer = {
    system = "aarch64-linux";
    module = {
      inputs,
      lib,
      ...
    }: let
      # Use a nixos-facter report if present, otherwise the committed
      # hardware-configuration.nix. Generate on the Pi itself: nixos-facter -o /tmp/pioneer.facter.json
      hardware =
        if builtins.pathExists ./_hw/pioneer.facter.json
        then [
          inputs.nixos-facter-modules.nixosModules.facter
          {facter.reportPath = ./_hw/pioneer.facter.json;}
        ]
        else [./_hw/hardware-configuration.nix];
    in {
      imports =
        (with nixos; [
          common
          server
          pangolin-newt
        ])
        ++ hardware
        ++ [
          inputs.nixos-hardware.nixosModules.raspberry-pi-3
        ];

      # Raspberry Pi has no grub bootloader.
      cosmos.system.boot.enable = lib.mkForce false;

      systemd.settings.Manager.RuntimeWatchdogSec = lib.mkForce "60s";

      system.stateVersion = "24.11";
    };
  };
}
