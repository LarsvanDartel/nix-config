{
  config,
  lib,
  pkgs,
  ...
}: let
  cfg = config.cosmos.desktops.common.styling.theme.nord;
  mode =
    if cfg.darkMode
    then ""
    else "-light";
in {
  options.cosmos.desktops.common.styling.theme.nord = {
    enable = lib.mkEnableOption "nord theme";
    darkMode = lib.mkEnableOption "dark mode";
  };

  config = lib.mkIf cfg.enable {
    cosmos.desktops.common.styling = {
      icons.theme = lib.mkDefault "nordzy";
      theme = {
        darkMode = lib.mkForce cfg.darkMode;
        colorScheme = "${pkgs.base16-schemes}/share/themes/nord${mode}.yaml";
      };
    };
  };
}
