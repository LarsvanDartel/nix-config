{
  config,
  lib,
  pkgs,
  ...
}: let
  inherit (lib.custom) get-non-default-nix-files;
  inherit (lib.types) listOf str;
  inherit (lib.options) mkEnableOption mkOption;
  inherit (lib.modules) mkIf;

  cfg = config.desktops.hyprland;
in {
  imports = get-non-default-nix-files ./.;

  options.desktops.hyprland = {
    enable = mkEnableOption "hyprland";

    exec-once-extras = mkOption {
      type = listOf str;
      default = [];
      description = "Extra commands to run once on Hyprland startup.";
    };
  };

  config = mkIf cfg.enable {
    nix.settings = {
      trusted-substituters = ["https://hyprland.cachix.org"];
      trusted-public-keys = [
        "hyprland.cachix.org-1:a7pgxzMz7+chwVL3/pzj6jIBMioiJM7ypFP8PwtkuGc="
      ];
    };

    cli.programs = {
      clipse.enable = true;
    };

    desktops.hyprland.addons = {
      hyprlock.enable = true;
      hyprpaper.enable = true;
      hyprshot.enable = true;
      mako.enable = true;
      rofi.enable = true;
      waybar.enable = true;
    };

    home.packages = with pkgs; [
      brightnessctl
      wl-clipboard
    ];
  };
}
