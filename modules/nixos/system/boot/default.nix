{
  config,
  lib,
  ...
}: let
  inherit (lib.options) mkEnableOption;
  inherit (lib.modules) mkIf;

  cfg = config.system.boot;
in {
  options.system.boot = {
    enable = mkEnableOption "boot configuration";
  };
  config = mkIf cfg.enable {
    boot = {
      loader = {
        efi = {
          canTouchEfiVariables = true;
        };
        grub = {
          devices = ["nodev"];
          efiSupport = true;
          enable = true;
          useOSProber = true;
        };
      };
    };
  };
}
