{
  config,
  lib,
  pkgs,
  ...
}: let
  cfg = config.modules.styling.themes.nord;
  mode =
    if cfg.darkMode
    then ""
    else "-light";
in {
  options.modules.styling.themes.nord = {
    enable = lib.mkEnableOption "nord theme";
    darkMode = lib.mkEnableOption "dark mode";
  };

  config = lib.mkIf cfg.enable {
    modules.styling.themes = {
      darkMode = lib.mkForce cfg.darkMode;
      colorScheme = "${pkgs.base16-schemes}/share/themes/nord${mode}.yaml";
    };
  };
}
