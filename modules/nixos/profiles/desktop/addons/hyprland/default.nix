{
  config,
  lib,
  ...
}: let
  inherit (lib.options) mkEnableOption;
  inherit (lib.modules) mkIf;

  cfg = config.cosmos.profiles.desktop.addons.hyprland;
in {
  options.cosmos.profiles.desktop.addons.hyprland = {
    enable = mkEnableOption "hyprland window manager";
  };

  config = mkIf cfg.enable {
    environment.sessionVariables.NIXOS_OZONE_WL = "1";

    programs.hyprland = {
      enable = true;
      xwayland.enable = true;
      withUWSM = true;
    };

    cosmos.profiles.desktop.addons.greetd.enable = true;
    cosmos.profiles.desktop.addons.xdg-portal.enable = true;
  };
}
