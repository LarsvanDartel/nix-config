{
  config,
  lib,
  pkgs,
  ...
}: let
  inherit (lib.cosmos) get-non-default-nix-files;
  inherit (lib.attrsets) attrsToList;
  inherit (lib.options) mkOption mkEnableOption;
  inherit (lib.types) nullOr str lines attrsOf anything;
  inherit (lib.strings) concatStrings;

  cfg = config.cosmos.desktops.common.styling.theme;
in {
  imports = get-non-default-nix-files ./.;

  options.cosmos.desktops.common.styling.theme = {
    colorScheme = mkOption {
      type = nullOr str;
      default = "${pkgs.base16-schemes}/share/themes/nord.yaml";
      description = "Base 16 color scheme";
    };

    darkMode = mkEnableOption "dark mode";

    schemeColors = mkOption {
      type = attrsOf anything;
      default = config.lib.stylix.colors;
      description = "Generated colors from scheme";
    };

    colors = with cfg.schemeColors; {
      bg0 = mkOption {
        type = str;
        default = base00;
      };
      fg0 = mkOption {
        type = str;
        default = base05;
      };
      bg1 = mkOption {
        type = str;
        default = base01;
      };
      fg1 = mkOption {
        type = str;
        default = base06;
      };
      bg2 = mkOption {
        type = str;
        default = base02;
      };
      fg2 = mkOption {
        type = str;
        default = base04;
      };
      accent = mkOption {
        type = str;
        default = base0C;
      };
      border = mkOption {
        type = str;
        default = base0F;
      };
    };

    colorsCSS = mkOption {
      type = lines;
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
