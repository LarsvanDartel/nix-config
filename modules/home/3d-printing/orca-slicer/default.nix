{
  config,
  lib,
  pkgs,
  ...
}: let
  inherit (lib.options) mkEnableOption;
  inherit (lib.modules) mkIf;

  cfg = config.cosmos."3d-printing".orca-slicer;
in {
  options.cosmos."3d-printing".orca-slicer = {
    enable = mkEnableOption "orca slicer";
  };

  config = mkIf cfg.enable {
    cosmos.system.impermanence.persist.directories = [
      ".config/OrcaSlicer"
      ".local/share/orca-slicer"
    ];

    home.packages = with pkgs; [orca-slicer];
  };
}
