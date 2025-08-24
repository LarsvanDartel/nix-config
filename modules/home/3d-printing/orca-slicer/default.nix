{
  config,
  lib,
  pkgs,
  ...
}: let
  inherit (lib.options) mkEnableOption;
  inherit (lib.modules) mkIf;

  cfg = config."3d-printing".orca-slicer;
in {
  options."3d-printing".orca-slicer = {
    enable = mkEnableOption "orca slicer";
  };

  config = mkIf cfg.enable {
    system.impermanence.persist.directories = [
      ".config/OrcaSlicer"
      ".local/share/orca-slicer"
    ];

    home.packages = with pkgs; [orca-slicer];
  };
}
