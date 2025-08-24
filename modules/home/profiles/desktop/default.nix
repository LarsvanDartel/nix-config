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

    cli.programs = {
      bluetuith.enable = true;
      pulsemixer.enable = true;
    };

    media = {
      mpv.enable = true;
      spotify.enable = true;
    };

    services = {
      kde-connect.enable = true;
    };

    social = {
      discord.enable = true;
      signal.enable = true;
    };
  };
}
