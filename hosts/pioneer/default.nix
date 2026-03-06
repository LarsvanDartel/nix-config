{
  inputs,
  lib,
  ...
}: let
  inherit (lib.modules) mkForce;
in {
  imports = [
    # Hardware
    ./hardware-configuration.nix
    inputs.nixos-hardware.nixosModules.raspberry-pi-3
  ];

  config = {
    cosmos = {
      system.boot.enable = mkForce false;

      profiles = {
        server.enable = true;
      };

      services.pangolin.newt.enable = true;
    };

    systemd.settings.Manager = {
      RuntimeWatchdogSec = mkForce "60s";
    };

    system.stateVersion = "24.11";
  };
}
