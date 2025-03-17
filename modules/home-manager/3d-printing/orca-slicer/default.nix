{
  config,
  lib,
  pkgs,
  ...
}: let
  cfg = config.modules."3d-printing".orca-slicer;
in {
  options.modules."3d-printing".orca-slicer = {
    enable = lib.mkEnableOption "orca slicer";
  };

  config = lib.mkIf cfg.enable {
    modules.persist.directories = [
      ".config/OrcaSlicer"
      ".local/share/orca-slicer"
    ];
    home.packages = with pkgs; [orca-slicer];
  };
}
