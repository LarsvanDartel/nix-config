{
  config,
  lib,
  pkgs,
  ...
}: let
  inherit (lib.options) mkEnableOption;
  inherit (lib.modules) mkIf;

  cfg = config.cli.terminals.alacritty;
in {
  options.cli.terminals.alacritty = {
    enable = mkEnableOption "alacritty";
  };

  config = mkIf cfg.enable {
    cli.terminals.default = "${pkgs.alacritty}/bin/alacritty";

    programs.alacritty = {
      enable = true;
    };
  };
}
