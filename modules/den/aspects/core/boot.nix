# core.boot aspect — grub bootloader + the cosmos.system.boot options (was
# flake.modules.nixos.common in modules/nixos/system/boot.nix). Opt-in per host
# (hosts without a bootloader, e.g. the Pi, don't include it), so it is NOT in
# roles.default.
{...}: {
  den.aspects.core.boot.nixos = {
    config,
    lib,
    ...
  }: let
    inherit (lib.options) mkOption;
    inherit (lib.types) bool int nullOr str;

    cfg = config.cosmos.system.boot;
  in {
    options.cosmos.system.boot = {
      configurationLimit = mkOption {
        type = int;
        default = 10;
        description = ''
          Generations kept in the boot menu. GRUB's own default is 100, which
          no EFI system partition can hold: each distinct kernel build costs
          its bzImage plus its initrd, and once the ESP fills, installing the
          bootloader fails *after* the system has already been built.

          Sized for a 512 MiB ESP at roughly 65 MiB per distinct kernel build.
          Generations sharing a nixpkgs revision share those files, so ten
          menu entries are normally two or three kernels' worth.
        '';
      };

      legacy = mkOption {
        type = bool;
        default = false;
        description = "Whether to use legacy BIOS";
      };
      grub-device = mkOption {
        type = nullOr str;
        default = null;
        description = "Device to install grub on";
      };
      detect-windows = mkOption {
        type = bool;
        default = false;
        description = "Whether to check for windows partitions";
      };
    };

    config = {
      assertions = [
        {
          assertion = !cfg.legacy || cfg.grub-device != null;
          message = "boot: grub device must be defined when using legacy BIOS";
        }
      ];
      boot.loader = {
        efi.canTouchEfiVariables = !cfg.legacy;
        grub = {
          enable = true;
          device =
            if cfg.grub-device == null
            then "nodev"
            else cfg.grub-device;
          efiSupport = !cfg.legacy;
          useOSProber = cfg.detect-windows;
          inherit (cfg) configurationLimit;
        };
      };
    };
  };
}
