# pioneer (Raspberry Pi 3, aarch64 server). den-produced; named `pioneer`
# during the migration to avoid colliding with the old `pioneer`.
#
# NOTE: pioneer can't use the clean facter path yet. The raspberry-pi-3 module
# sets nixpkgs.overlays (a makeModulesClosure fix), and that combined with any
# module setting nixpkgs.hostPlatform (facter's report, or the hardware file)
# recurses under den. As a stopgap we import the nixos-generate-config hardware
# file eagerly with its `nixpkgs` attr stripped (so only rpi3's overlay touches
# nixpkgs, which alone is fine). TODO: move pioneer to facter once the rpi3
# overlay is applied globally (via core.nixpkgs) instead of by the module.
{
  den,
  inputs,
  ...
}: let
  hardware =
    builtins.removeAttrs
    (import ./_hw/pioneer/hardware-configuration.nix {
      lib = inputs.nixpkgs.lib;
      modulesPath = inputs.nixpkgs + "/nixos/modules";
      config = {};
      pkgs = {};
    })
    ["nixpkgs"];
in {
  den.hosts.aarch64-linux.pioneer.users.nixos = {};

  den.aspects.pioneer = {
    includes = with den.aspects; [
      roles.server
      services.pangolin.newt
    ];

    nixos = {lib, ...}: {
      imports = [
        hardware
        inputs.nixos-hardware.nixosModules.raspberry-pi-3
      ];

      systemd.settings.Manager.RuntimeWatchdogSec = lib.mkForce "60s";

      system.stateVersion = "24.11";
    };
  };
}
