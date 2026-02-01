{
  config,
  lib,
  ...
}: let
  inherit (lib.options) mkEnableOption;
  inherit (lib.modules) mkIf;

  cfg = config.cosmos.profiles.desktop;
in {
  options.cosmos.profiles.desktop = {
    enable = mkEnableOption "desktop configuration";
  };
  config = mkIf cfg.enable {
    cosmos = {
      profiles = {
        common.enable = true;
        desktop.addons = {
          fontconfig.enable = true;
        };
      };

      networking.networkmanager.enable = true;

      hardware = {
        audio.enable = true;
        bluetoothctl.enable = true;
      };

      cli.programs = {
        nh.enable = true;
      };

      user.name = "lvdar";
    };
  };
}
