{
  config,
  lib,
  pkgs,
  ...
}: let
  inherit (lib.options) mkEnableOption;
  inherit (lib.modules) mkIf;

  cfg = config.cosmos.cli.programs.xh;
in {
  options.cosmos.cli.programs.xh = {
    enable = mkEnableOption "xh";
  };

  config = mkIf cfg.enable {
    home.packages = with pkgs; [
      xh
    ];
  };
}
