{
  config,
  lib,
  pkgs,
  ...
}: let
  inherit (lib.options) mkEnableOption;
  inherit (lib.modules) mkIf;

  cfg = config.cosmos.cli.terminals.alacritty;
in {
  options.cosmos.cli.terminals.alacritty = {
    enable = mkEnableOption "alacritty";
  };

  config = mkIf cfg.enable {
    cosmos.cli.terminals.default = "${pkgs.alacritty}/bin/alacritty";

    programs.alacritty = {
      enable = true;
    };
  };
}
