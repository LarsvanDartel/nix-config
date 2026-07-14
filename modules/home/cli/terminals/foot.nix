{config, ...}: let
  inherit (config.flake.modules.homeManager) terminals;
in {
  flake.modules.homeManager.desktop = {
    config,
    lib,
    pkgs,
    ...
  }: let
    inherit (lib.modules) mkDefault mkOrder mkForce;
  in {
    imports = [terminals];

    cosmos.cli.terminals.default = mkDefault "${pkgs.foot}/bin/footclient";
    cosmos.cli.terminals.defaultStandalone = mkDefault "${pkgs.foot}/bin/foot";

    cosmos.desktops.hyprland.exec-once-extras = mkOrder 200 ["${pkgs.foot}/bin/foot --server"];

    programs.foot = {
      enable = true;
      settings.main = let
        font = config.cosmos.desktops.common.styling.fonts.monospace.name;
        size = toString config.cosmos.desktops.common.styling.fonts.monospace.recommendedSize;
      in {
        font = mkForce "${font}:style=Regular:size=${size}";
        font-bold = mkForce "${font}:style=Bold:size=${size}";
        font-italic = mkForce "${font}:style=Italic:size=${size}";
        font-bold-italic = mkForce "${font}:style=Bold Italic:size=${size}";
      };
    };
  };
}
