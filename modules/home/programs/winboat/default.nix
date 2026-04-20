{
  config,
  lib,
  pkgs,
  ...
}: let
  inherit (lib.options) mkEnableOption;
  inherit (lib.modules) mkIf;

  cfg = config.cosmos.programs.winboat;
in {
  options.cosmos.programs.winboat = {
    enable = mkEnableOption "winboat";
  };

  config = mkIf cfg.enable {
    home.packages = [
      pkgs.freerdp
      pkgs.winboat
    ];

    cosmos.system.impermanence.persist.directories = [
      "winboat"
      ".winboat"
      ".config/winboat"
      ".local/share/containers"
    ];
  };
}
