{
  config,
  lib,
  pkgs,
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
    system.impermanence.persist.directories = [".local/share/Steam"];

    home.packages = with pkgs; [
      steam
    ];
  };
}
