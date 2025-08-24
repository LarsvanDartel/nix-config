{
  config,
  lib,
  pkgs,
  ...
}: let
  inherit (lib.options) mkEnableOption;
  inherit (lib.modules) mkIf mkDefault mkOrder mkForce;

  cfg = config.cli.terminals.foot;
in {
  options.cli.terminals.foot = {
    enable = mkEnableOption "foot";
  };

  config = mkIf cfg.enable {
    cli.terminals.default = mkDefault "${pkgs.foot}/bin/footclient";
    cli.terminals.defaultStandalone = mkDefault "${pkgs.foot}/bin/foot";

    desktops.hyprland.exec-once-extras = mkOrder 200 ["${pkgs.foot}/bin/foot --server"];

    programs.foot = {
      enable = true;
      settings.main = let
        font = config.styling.fonts.monospace.name;
        size = toString config.styling.fonts.monospace.recommendedSize;
      in {
        font = mkForce "${font}:style=Regular:size=${size}";
        font-bold = mkForce "${font}:style=Bold:size=${size}";
        font-italic = mkForce "${font}:style=Italic:size=${size}";
        font-bold-italic = mkForce "${font}:style=Bold Italic:size=${size}";
      };
    };
  };
}
