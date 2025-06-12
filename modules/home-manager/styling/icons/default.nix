{
  config,
  lib,
  pkgs,
  ...
}: let
  inherit (lib.attrsets) attrNames;
  inherit (lib.types) nullOr enum str;

  icon-themes = {
    "adwaita" = {
      package = pkgs.adwaita-icon-theme;
      light-name = "Adwaita";
      dark-name = "Adwaita";
    };
    "nordzy" = {
      package = pkgs.nordzy-icon-theme;
      light-name = "Nordzy";
      dark-name = "Nordzy-dark";
    };
    # TODO: Add more icon themes
  };
  default-icon-theme = "adwaita";

  cfg = config.modules.styling.icons;
in {
  options.modules.styling.icons = {
    theme = lib.mkOption {
      type = enum (attrNames icon-themes);
      default = default-icon-theme;
      description = "The icon theme to use.";
    };
    name = lib.mkOption {
      type = nullOr str;
      default = null;
      description = "The name of the icon theme. If null, the default name will be used.";
    };
  };
  config = {
    stylix.iconTheme = with icon-themes.${cfg.theme}; {
      enable = true;
      inherit package;
      light =
        if cfg.name == null
        then light-name
        else cfg.name;
      dark =
        if cfg.name == null
        then dark-name
        else cfg.name;
    };
  };
}
