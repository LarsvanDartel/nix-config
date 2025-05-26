{
  config,
  lib,
  pkgs,
  ...
}: let
  inherit (lib.options) mkEnableOption;
  inherit (lib.modules) mkIf;

  cfg = config.modules.terminal.programs.xh;
in {
  options.modules.terminal.programs.xh = {
    enable = mkEnableOption "xh";
  };

  config = mkIf cfg.enable {
    home.packages = with pkgs; [
      xh
    ];
  };
}
