{
  config,
  lib,
  pkgs,
  ...
}:
with lib; let
  cfg = config.hyprland;
in {
  options.hyprland = {
    enable = mkEnableOption "Enable Hyprland";
  };

  config = mkIf cfg.enable {
    wayland.windowManager.hyprland = {
      enable = true;
      settings = {
        "$mainMod" = "SUPER";
        "$terminal" = "alacritty";
        # "$fileManager" = "$terminal -e sh -c 'ranger'";
        # "$menu" = "rofi";

        env = [
          "NIXOS_OZONE_WL,1"
          "WLR_NO_HARDWARE_CURSORS,1"
        ];

        monitor = ",1980x1080@60,auto,1";

        exec-once = [
          # "waybar"
        ];

        # general = {
        #   gaps_in = 10;
        #   gaps_out = 10;
        #
        #   border_size = 5;
        #
        #   layout = "master";
        # };

        input = {
          kb_layout = "us";
          kb_variant = "dvp";
          kb_options = "caps:escape";
        };

        bind = [
          "$mainMod SHIFT, Return, exec, $terminal"
          "$mainMod SHIFT, C, killactive"
          "$mainMod SHIFT, Q, exit"
        ];
      };
    };
  };
}
