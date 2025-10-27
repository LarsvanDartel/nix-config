{
  config,
  lib,
  ...
}: let
  inherit (lib.options) mkEnableOption;
  inherit (lib.modules) mkIf;

  cfg = config.cosmos.desktops.hyprland.addons.hyprshot;
in {
  options.cosmos.desktops.hyprland.addons.hyprshot = {
    enable = mkEnableOption "hyprshot";
  };

  config = mkIf cfg.enable {
    programs.hyprshot = {
      enable = true;
      saveLocation = "~/screenshots";
    };
  };
}
