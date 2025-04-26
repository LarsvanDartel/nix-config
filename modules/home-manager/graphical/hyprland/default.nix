{
  config,
  lib,
  pkgs,
  ...
}: let
  cfg = config.modules.graphical.hyprland;
in {
  imports = [
    ./binds.nix
    ./hyprlock.nix
    ./hyprpaper.nix
    ./rules.nix
    ./settings.nix
  ];

  options.modules.graphical.hyprland = {
    enable = lib.mkEnableOption "hyprland";
  };

  config = lib.mkIf cfg.enable {
    modules.graphical = {
      waybar.enable = lib.mkForce true;
      rofi.enable = lib.mkForce true;
      mako.enable = lib.mkForce true;
    };

    home.packages = with pkgs; [
      kdePackages.xwaylandvideobridge
      wl-clipboard
      brightnessctl
    ];

    wayland.windowManager.hyprland.enable = true;
  };
}
