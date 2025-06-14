{
  config,
  lib,
  osConfig,
  pkgs,
  ...
}: let
  inherit (lib.options) mkEnableOption;
  inherit (lib.modules) mkIf;

  cfg = config.modules.gaming.launchers.lutris;
in {
  options.modules.gaming.launchers.lutris = {
    enable = mkEnableOption "lutris";
  };

  options.systemwide.lutris = {
    enable = mkEnableOption "lutris";
  };

  config = mkIf cfg.enable {
    systemwide.lutris.enable = true;

    modules.persist.directories = [".local/share/lutris"];

    programs.lutris = {
      enable = true;
      protonPackages = with pkgs; [proton-ge-bin];
      steamPackage = osConfig.programs.steam.package;
      winePackages = with pkgs; [
        wineWowPackages.waylandFull
      ];
    };
  };
}
