{
  config,
  lib,
  ...
}: let
  cfg = config.modules.bluetooth;
in {
  options.modules.bluetooth = {
    enable = lib.mkEnableOption "bluetooth";
  };

  config = lib.mkIf cfg.enable {
    modules.persist.directories = ["/var/lib/bluetooth"];
    hardware = {
      bluetooth.enable = true;
      bluetooth.powerOnBoot = true;
    };
  };
}
