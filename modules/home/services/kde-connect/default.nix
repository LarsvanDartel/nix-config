{
  config,
  lib,
  ...
}: let
  inherit (lib.options) mkEnableOption;
  inherit (lib.modules) mkIf;

  cfg = config.cosmos.services.kde-connect;
in {
  options.cosmos.services.kde-connect = {
    enable = mkEnableOption "KDE Connect";
  };

  config = mkIf cfg.enable {
    cosmos.system.impermanence.persist.directories = [".config/kdeconnect"];

    # Hide all .desktop, except for org.kde.kdeconnect.settings
    xdg.desktopEntries = {
      "org.kde.kdeconnect.sms" = {
        exec = "";
        name = "KDE Connect SMS";
        settings.NoDisplay = "true";
      };
      "org.kde.kdeconnect.nonplasma" = {
        exec = "";
        name = "KDE Connect Indicator";
        settings.NoDisplay = "true";
      };
      "org.kde.kdeconnect.app" = {
        exec = "";
        name = "KDE Connect";
        settings.NoDisplay = "true";
      };
    };

    services.kdeconnect = {
      enable = true;
      indicator = true;
    };
  };
}
