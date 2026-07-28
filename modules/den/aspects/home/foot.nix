# home.foot — foot terminal (server mode) + terminal defaults + hyprland
# exec-once. Depends on home.terminals (default option) and, for the exec-once,
# the hyprland _impl option (present on hyprland hosts).
{den, ...}: {
  den.aspects.home.foot = {
    includes = [den.aspects.home.terminals];
    homeManager = {
      config,
      lib,
      pkgs,
      ...
    }: let
      inherit (lib.modules) mkDefault mkOrder mkForce;
    in {
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
  };
}
