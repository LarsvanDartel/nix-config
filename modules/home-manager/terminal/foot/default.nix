{
  config,
  lib,
  pkgs,
  ...
}: let
  cfg = config.modules.terminal.foot;
in {
  options.modules.terminal.foot = {
    enable = lib.mkEnableOption "foot";
  };

  config = lib.mkIf cfg.enable {
    modules.terminal.default = lib.mkDefault "${pkgs.foot}/bin/footclient";
    modules.graphical.startupCommands = ["${pkgs.foot}/bin/foot --server"];

    programs.foot = {
      enable = true;
      settings.main = let
        font = config.modules.styling.fonts.monospace.name;
        size = toString config.modules.styling.fonts.monospace.recommendedSize;
      in {
        font = lib.mkForce "${font}:style=Regular:size=${size}";
        font-bold = lib.mkForce "${font}:style=Bold:size=${size}";
        font-italic = lib.mkForce "${font}:style=Italic:size=${size}";
        font-bold-italic = lib.mkForce "${font}:style=Bold Italic:size=${size}";
      };
    };
  };
}
