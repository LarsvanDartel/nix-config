{
  config,
  lib,
  ...
}: let
  inherit (lib.options) mkEnableOption;
  inherit (lib.modules) mkIf;

  cfg = config.cosmos.gaming.launchers.steam;
in {
  options.cosmos.gaming.launchers.steam = {
    enable = mkEnableOption "steam";
  };

  config = mkIf cfg.enable {
    cosmos.system.impermanence.persist.directories = [".local/share/Steam" ".config/unity3d"];
  };
}
