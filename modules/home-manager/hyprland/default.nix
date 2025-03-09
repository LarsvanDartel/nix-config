{
  config,
  lib,
  pkgs,
  ...
}: let
  cfg = config.modules.hyprland;
in {
  imports = [
    ./binds.nix
    ./rules.nix
    ./settings.nix
  ];

  options.modules.hyprland = {
    enable = lib.mkEnableOption "hyprland";
  };

  config = lib.mkIf cfg.enable {
    modules.waybar.enable = lib.mkForce true;
    wayland.windowManager.hyprland.enable = true;
  };
}
