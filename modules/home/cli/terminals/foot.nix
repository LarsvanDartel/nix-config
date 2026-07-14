# foot. The portable `programs.foot` lives in its own named module (themed by the
# stylix base when wrapped); the desktop-specific bits — server mode, terminal
# defaults, hyprland exec-once, and the explicit Cozette font override — stay in
# the `desktop` aggregate, which imports the named module.
{config, ...}: let
  inherit (config.flake.modules.homeManager) terminals foot;
in {
  flake.modules.homeManager.foot = {...}: {
    programs.foot.enable = true;
  };

  flake.modules.homeManager.desktop = {
    config,
    lib,
    pkgs,
    ...
  }: let
    inherit (lib.modules) mkDefault mkOrder mkForce;
  in {
    imports = [terminals foot];

    cosmos.cli.terminals.default = mkDefault "${pkgs.foot}/bin/footclient";
    cosmos.cli.terminals.defaultStandalone = mkDefault "${pkgs.foot}/bin/foot";

    cosmos.desktops.hyprland.exec-once-extras = mkOrder 200 ["${pkgs.foot}/bin/foot --server"];

    programs.foot.settings.main = let
      font = config.cosmos.desktops.common.styling.fonts.monospace.name;
      size = toString config.cosmos.desktops.common.styling.fonts.monospace.recommendedSize;
    in {
      font = mkForce "${font}:style=Regular:size=${size}";
      font-bold = mkForce "${font}:style=Bold:size=${size}";
      font-italic = mkForce "${font}:style=Italic:size=${size}";
      font-bold-italic = mkForce "${font}:style=Bold Italic:size=${size}";
    };
  };
}
