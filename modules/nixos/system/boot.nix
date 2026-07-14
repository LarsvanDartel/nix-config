{...}: {
  flake.modules.nixos.common = {
    config,
    lib,
    ...
  }: let
    inherit (lib.options) mkOption mkEnableOption;
    inherit (lib.modules) mkIf;
    inherit (lib.types) bool nullOr str;

    cfg = config.cosmos.system.boot;
  in {
    options.cosmos.system.boot = {
      # Internal: on when imported (via common). A host without a bootloader
      # (e.g. the Raspberry Pi) sets this false.
      enable = mkEnableOption "boot configuration" // {default = true;};
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

    config = mkIf cfg.enable {
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
        };
      };
    };
  };
}
