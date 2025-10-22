{
  config,
  lib,
  ...
}: let
  inherit (lib.options) mkEnableOption;
  inherit (lib.modules) mkIf;

  cfg = config.hardware.cdrom;
in {
  options.hardware.cdrom = {
    enable = mkEnableOption "cdrom support";
  };

  config = mkIf cfg.enable {
    user.extraGroups = ["cdrom"];

    boot.kernelModules = ["sg" "sr_mod" "cdrom"];

    services.udev.extraRules = ''
      KERNEL=="sr[0-9]*", GROUP="cdrom", MODE="0660"
    '';
  };
}
