# home.foot — foot as a nix-wrapper-modules package (`nix run .#foot`); the
# wrapper holds the config with both palettes, home-manager installs it per
# mode (cosmosStyling.modal) and sets the terminal defaults.
{
  den,
  inputs,
  cosmosStyling,
  lib,
  ...
}: let
  # `mode` only picks the palette new windows start in: both are loaded, and
  # SIGUSR1/SIGUSR2 switch a running foot to dark/light (home.theme's onSwitch).
  mkFoot = pkgs: mode: let
    monospace = cosmosStyling.font pkgs cosmosStyling.fonts.monospace;
    font = monospace.name;
    # A pixel font in points (9pt is 12px at 96 dpi) is drawn off its grid.
    size =
      if monospace.pixelGrid != null
      then "pixelsize=${toString monospace.pixelGrid}"
      else "size=${toString monospace.recommendedSize}";
    # stylix's foot target.
    palette = palette: let
      colors = cosmosStyling.colors pkgs palette;
    in {
      # The light background at the shared 0.8 all but hides the wallpaper.
      alpha =
        if palette == "light"
        then 0.65
        else cosmosStyling.opacity.terminal;
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
  in
    inputs.nix-wrapper-modules.wrappers.foot.wrap {
      inherit pkgs;
      settings =
        {
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
              initial-color-theme = mode;
            }
            # Zoom (ctrl +/-) a whole grid step at a time instead of 0.5pt.
            // lib.optionalAttrs (monospace.pixelGrid != null) {
              font-size-adjustment = "${toString monospace.pixelGrid}px";
            };
        }
        // lib.listToAttrs (map (m: lib.nameValuePair "colors-${m}" (palette m)) cosmosStyling.modes);
    };
in {
  perSystem = {pkgs, ...}: {packages.foot = mkFoot pkgs cosmosStyling.defaultMode;};

  den.aspects.home.foot = {
    includes = [den.aspects.home.terminals];
    homeManager = {
      config,
      lib,
      pkgs,
      ...
    }: let
      inherit (lib.modules) mkDefault;
      foot = config.cosmos.desktops.common.styling.modes.modal "foot" (mkFoot pkgs);
    in {
      home.packages = [foot];

      cosmos.desktops.common.styling.modes.onSwitch = ''
        if [ "$mode" = light ]; then sig=USR2; else sig=USR1; fi
        pkill -"$sig" -x foot || true
      '';

      # No foot server runs (it was started by Hyprland's exec-once).
      cosmos.cli.terminals.default = mkDefault "${foot}/bin/foot";
      cosmos.cli.terminals.defaultStandalone = mkDefault "${foot}/bin/foot";
    };
  };
}
