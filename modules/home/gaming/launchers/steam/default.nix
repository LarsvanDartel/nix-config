{
  config,
  lib,
  ...
}: let
  inherit (lib.options) mkEnableOption;
  inherit (lib.modules) mkIf;

  cfg = config.gaming.launchers.steam;
in {
  options.gaming.launchers.steam = {
    enable = mkEnableOption "steam";
  };

  config = mkIf cfg.enable {
    system.impermanence.persist.directories = [".local/share/Steam" ".config/unity3d"];
  };
}
