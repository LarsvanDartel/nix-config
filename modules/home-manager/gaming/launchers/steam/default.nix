{
  config,
  lib,
  ...
}: let
  inherit (lib.options) mkEnableOption;
  inherit (lib.modules) mkIf;

  cfg = config.modules.gaming.launchers.steam;
in {
  options.modules.gaming.launchers.steam = {
    enable = mkEnableOption "steam";
  };

  options.systemwide.steam = {
    enable = mkEnableOption "steam";
  };

  config = mkIf cfg.enable {
    systemwide.steam.enable = true;
    modules.persist.directories = [".local/share/Steam"];
  };
}
