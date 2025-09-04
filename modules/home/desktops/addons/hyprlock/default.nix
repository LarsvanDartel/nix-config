{
  config,
  lib,
  ...
}: let
  inherit (lib.options) mkEnableOption;
  inherit (lib.modules) mkIf;

  cfg = config.desktops.addons.hyprlock;
in {
  options.desktops.addons.hyprlock = {
    enable = mkEnableOption "hyprlock";
  };

  config = mkIf cfg.enable {
    stylix.targets.hyprlock.enable = false;
    programs.hyprlock = {
      enable = true;
      settings = {
        general = {
          disable_loading_bar = true;
          immediate_render = true;
          hide_cursor = false;
          no_fade_in = true;
        };

        animation = [
          "inputFieldDots, 1, 2, linear"
          "fadeIn, 0"
        ];

        background = [
          {
            inherit (config.styling.wallpaper) path;
          }
        ];

        input-field = with config.lib.stylix.colors; [
          {
            size = "300, 50";
            valign = "bottom";
            position = "0%, 10%";

            outline_thickness = 3;

            font_color = "rgb(${base00})";
            outer_color = "rgb(${base0F})";
            inner_color = "rgb(${base04})";
            check_color = "rgb(${base0A})";
            fail_color = "rgb(${base08})";

            fade_on_empty = false;
            placeholder_text = "Enter Password";

            dots_spacing = 0.2;
            dots_center = true;
            dots_fade_time = 100;
          }
        ];

        label = with config.lib.stylix.colors; [
          {
            text = "$TIME";
            font_size = 150;
            color = "rgb(${base04})";

            position = "0%, 30%";

            valign = "center";
            halign = "center";
          }
          {
            text = "cmd[update:3600000] date +'%a %b %d'";
            font_size = 20;
            color = "rgb(${base04})";

            position = "0%, 40%";

            valign = "center";
            halign = "center";
          }
        ];
      };
    };
  };
}
