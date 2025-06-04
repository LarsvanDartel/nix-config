{
  config,
  lib,
  ...
}: let
  inherit (lib.options) mkEnableOption;
  inherit (lib.modules) mkIf;

  cfg = config.modules.kde-connect;
in {
  options.modules.kde-connect = {
    enable = mkEnableOption "KDE Connect integration";
  };

  options.systemwide.kde-connect = {
    enable = mkEnableOption "KDE Connect service";
  };

  config = mkIf cfg.enable {
    systemwide.kde-connect.enable = true;
    modules.persist.directories = [".config/kdeconnect"];

    services.kdeconnect = {
      enable = true;
      indicator = true;
    };
  };
}
