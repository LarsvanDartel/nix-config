{
  config,
  lib,
  pkgs,
  ...
}: let
  inherit (lib.options) mkEnableOption;
  inherit (lib.modules) mkIf;

  cfg = config.cli.programs.xh;
in {
  options.cli.programs.xh = {
    enable = mkEnableOption "xh";
  };

  config = mkIf cfg.enable {
    home.packages = with pkgs; [
      xh
    ];
  };
}
