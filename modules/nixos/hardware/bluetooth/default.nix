{
  config,
  lib,
  ...
}: let
  inherit (lib.options) mkEnableOption;
  inherit (lib.modules) mkIf;

  cfg = config.hardware.bluetoothctl;
in {
  options.hardware.bluetoothctl = {
    enable = mkEnableOption "bluetooth service";
  };

  config = mkIf cfg.enable {
    system.impermanence.persist.directories = ["/var/lib/bluetooth"];

    services.blueman.enable = true;
    hardware.bluetooth = {
      enable = true;
      powerOnBoot = false;
    };
  };
}
