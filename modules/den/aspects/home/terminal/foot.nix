# home.foot — foot as a nix-wrapper-modules package (`nix run .#foot`); the
# wrapper holds the config. home-manager installs it, sets the terminal
# defaults and (on hyprland hosts) starts `foot --server` for footclient.
{
  den,
  inputs,
  cosmosStyling,
  lib,
  ...
}: let
  mkFoot = pkgs: let
    colors = cosmosStyling.colors pkgs;
    monospace = cosmosStyling.font pkgs cosmosStyling.fonts.monospace;
    font = monospace.name;
    # A pixel font in points (9pt is 12px at 96 dpi) is drawn off its grid.
    size =
      if monospace.pixelGrid != null
      then "pixelsize=${toString monospace.pixelGrid}"
      else "size=${toString monospace.recommendedSize}";
    colorTheme =
      if cosmosStyling.darkMode
      then "dark"
      else "light";
  in
    inputs.nix-wrapper-modules.wrappers.foot.wrap {
      inherit pkgs;
      settings = {
        main =
          {
            font = "${font}:${size}";
            font-bold =
              if monospace.boldFamily != null
              then "${monospace.boldFamily}:${size}"
              else "${font}:style=Bold:${size}";
            font-italic = "${font}:style=Italic:${size}";
            font-bold-italic = "${font}:style=Bold Italic:${size}";
            dpi-aware = "no";
            initial-color-theme = colorTheme;
          }
          # Zoom (ctrl +/-) a whole grid step at a time instead of 0.5pt.
          // lib.optionalAttrs (monospace.pixelGrid != null) {
            font-size-adjustment = "${toString monospace.pixelGrid}px";
          };
        # stylix's foot target.
        "colors-${colorTheme}" = {
          alpha = cosmosStyling.opacity.terminal;
          foreground = colors.base05;
          background = colors.base00;
          regular0 = colors.base00;
          regular1 = colors.base08;
          regular2 = colors.base0B;
          regular3 = colors.base0A;
          regular4 = colors.base0D;
          regular5 = colors.base0E;
          regular6 = colors.base0C;
          regular7 = colors.base05;
          bright0 = colors.base03;
          bright1 = colors.base08;
          bright2 = colors.base0B;
          bright3 = colors.base0A;
          bright4 = colors.base0D;
          bright5 = colors.base0E;
          bright6 = colors.base0C;
          bright7 = colors.base07;
          "16" = colors.base09;
          "17" = colors.base0F;
          "18" = colors.base01;
          "19" = colors.base02;
          "20" = colors.base04;
          "21" = colors.base06;
        };
      };
    };
in {
  perSystem = {pkgs, ...}: {packages.foot = mkFoot pkgs;};

  den.aspects.home.foot = {
    includes = [den.aspects.home.terminals];
    homeManager = {
      lib,
      pkgs,
      ...
    }: let
      inherit (lib.modules) mkDefault mkOrder;
      foot = mkFoot pkgs;
    in {
      home.packages = [foot];

      cosmos.cli.terminals.default = mkDefault "${foot}/bin/footclient";
      cosmos.cli.terminals.defaultStandalone = mkDefault "${foot}/bin/foot";

      cosmos.desktops.hyprland.exec-once-extras = mkOrder 200 ["${foot}/bin/foot --server"];
    };
  };
}
