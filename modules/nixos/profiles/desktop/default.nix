{
  config,
  lib,
  ...
}: let
  inherit (lib.options) mkEnableOption;
  inherit (lib.modules) mkIf;

  cfg = config.profiles.desktop;
in {
  options.profiles.desktop = {
    enable = mkEnableOption "desktop configuration";
  };
  config = mkIf cfg.enable {
    profiles = {
      common.enable = true;
    };

    hardware = {
      audio.enable = true;
      bluetoothctl.enable = true;
    };

    cli.programs = {
      nh.enable = true;
    };

    user.name = "lvdar";
  };
}
