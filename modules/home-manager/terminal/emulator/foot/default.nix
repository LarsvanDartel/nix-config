{
  config,
  lib,
  pkgs,
  ...
}: let
  inherit (lib.options) mkEnableOption;
  inherit (lib.modules) mkIf mkDefault mkOrder mkForce;

  cfg = config.modules.terminal.emulator.foot;
in {
  options.modules.terminal.emulator.foot = {
    enable = mkEnableOption "foot";
  };

  config = mkIf cfg.enable {
    modules = {
      terminal.default = mkDefault "${pkgs.foot}/bin/footclient";
      terminal.defaultStandalone = mkDefault "${pkgs.foot}/bin/foot";
      graphical.startupCommands = mkOrder 200 ["${pkgs.foot}/bin/foot --server"];
    };

    programs.foot = {
      enable = true;
      settings.main = let
        font = config.modules.styling.fonts.monospace.name;
        size = toString config.modules.styling.fonts.monospace.recommendedSize;
      in {
        font = mkForce "${font}:style=Regular:size=${size}";
        font-bold = mkForce "${font}:style=Bold:size=${size}";
        font-italic = mkForce "${font}:style=Italic:size=${size}";
        font-bold-italic = mkForce "${font}:style=Bold Italic:size=${size}";
      };
    };
  };
}
