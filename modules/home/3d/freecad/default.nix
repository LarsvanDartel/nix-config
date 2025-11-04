{
  config,
  lib,
  pkgs,
  ...
}: let
  inherit (lib.options) mkEnableOption;
  inherit (lib.modules) mkIf;

  cfg = config.cosmos."3d".freecad;
in {
  options.cosmos."3d".freecad = {
    enable = mkEnableOption "freecad";
  };

  config = mkIf cfg.enable {
    cosmos.system.impermanence.persist.directories = [
      ".local/share/FreeCAD"
    ];

    home.packages = with pkgs; [freecad];
  };
}
