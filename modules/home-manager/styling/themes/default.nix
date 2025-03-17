{
  config,
  lib,
  ...
}:
with lib; let
  cfg = config.modules.styling.theme;
in {
  imports = [
    ./nord.nix
  ];

  options.modules.styling.theme = {
    colorScheme = mkOption {
      type = types.nullOr types.str;
      default = null;
      description = "Base 16 color scheme";
    };

    darkMode = lib.mkEnableOption "dark mode";

    schemeColors = mkOption {
      type = types.attrsOf types.anything;
      default = config.lib.stylix.colors;
      description = "Generated colors from scheme";
    };

    colors = with cfg.schemeColors; {
      bg0 = mkOption {
        type = types.str;
        default = base00;
      };
      fg0 = mkOption {
        type = types.str;
        default = base05;
      };
      bg1 = mkOption {
        type = types.str;
        default = base01;
      };
      fg1 = mkOption {
        type = types.str;
        default = base06;
      };
      bg2 = mkOption {
        type = types.str;
        default = base02;
      };
      fg2 = mkOption {
        type = types.str;
        default = base04;
      };
      accent = mkOption {
        type = types.str;
        default = base0C;
      };
      border = mkOption {
        type = types.str;
        default = base0F;
      };
    };

    colorsCSS = mkOption {
      type = types.lines;
      default =
        ":root {\n"
        + concatStrings (
          map (color: "  --nix-color-${color.name}: #${color.value};\n") (attrsToList cfg.colors)
        )
        + "}\n\n";
      description = "Colors as css variables";
    };
  };

  config = {
    stylix = {
      base16Scheme = cfg.colorScheme;
      polarity =
        if cfg.darkMode
        then "dark"
        else "light";
    };
  };
}
