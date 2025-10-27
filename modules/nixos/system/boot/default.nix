{
  config,
  lib,
  ...
}: let
  inherit (lib.options) mkEnableOption mkOption;
  inherit (lib.types) bool nullOr str;
  inherit (lib.modules) mkIf;

  cfg = config.cosmos.system.boot;
in {
  options.cosmos.system.boot = {
    enable = mkEnableOption "boot configuration";
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
}
