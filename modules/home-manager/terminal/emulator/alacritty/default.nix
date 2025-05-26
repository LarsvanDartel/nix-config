{
  config,
  lib,
  pkgs,
  ...
}: let
  inherit (lib.options) mkEnableOption;
  inherit (lib.modules) mkIf;

  cfg = config.modules.terminal.emulator.alacritty;
in {
  options.modules.terminal.emulator.alacritty = {
    enable = mkEnableOption "alacritty";
  };

  config = mkIf cfg.enable {
    modules.terminal.default = "${pkgs.alacritty}/bin/alacritty";

    programs.alacritty = {
      enable = true;
    };
  };
}
