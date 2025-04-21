{
  config,
  lib,
  pkgs,
  ...
}: let
  inherit (lib.options) mkEnableOption;
  inherit (lib.modules) mkIf;

  cfg = config.modules."3d-printing".orca-slicer;
in {
  options.modules."3d-printing".orca-slicer = {
    enable = mkEnableOption "orca slicer";
  };
  options.systemwide.orca-slicer = {
    enable = mkEnableOption "orca slicer";
  };

  config = mkIf cfg.enable {
    systemwide.orca-slicer.enable = true;

    modules.persist.directories = [
      ".config/OrcaSlicer"
      ".local/share/orca-slicer"
    ];
    home.packages = with pkgs; [orca-slicer];
  };
}
