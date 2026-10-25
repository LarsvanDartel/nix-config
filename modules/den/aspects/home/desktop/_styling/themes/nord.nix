{
  config,
  lib,
  ...
}: let
  cfg = config.cosmos.desktops.common.styling.theme.nord;
in {
  options.cosmos.desktops.common.styling.theme.nord = {
    enable = lib.mkEnableOption "nord theme";
    darkMode = lib.mkEnableOption "dark mode";
  };

  # The scheme file itself is set by desktop.styling (cosmosStyling.schemeFile).
  config = lib.mkIf cfg.enable {
    cosmos.desktops.common.styling = {
      icons.theme = lib.mkDefault "nordzy";
      theme.darkMode = lib.mkForce cfg.darkMode;
    };
  };
}
