{
  config,
  lib,
  ...
}: let
  inherit (lib.modules) mkIf;

  colors = config.lib.stylix.colors;
  rgb = color: "rgb(${color})";
  rgba = color: alpha: "rgba(${color}${alpha})";
in {
  # Stylix's Hyprland target stays off in Lua mode: it emits flat hyprlang names
  # ("col.active_border") but hl.config({}) takes the nested HL.ConfigOpt shape
  # (per hyprland-0.56.2's hl.meta.lua). Drop this file if stylix emits nested `col`.
  config = mkIf config.wayland.windowManager.hyprland.enable {
    stylix.targets.hyprland.enable = false;

    wayland.windowManager.hyprland.settings.config = {
      general.col = {
        active_border = rgb colors.base0D;
        inactive_border = rgb colors.base03;
      };

      group = {
        col = {
          border_active = rgb colors.base0D;
          border_inactive = rgb colors.base03;
          border_locked_active = rgb colors.base0C;
        };
        groupbar = {
          text_color = rgb colors.base05;
          col = {
            active = rgb colors.base0D;
            inactive = rgb colors.base03;
          };
        };
      };

      misc.background_color = rgb colors.base00;

      # Disabling the target loses this too; shadows would stay default black.
      decoration.shadow.color = rgba colors.base00 "99";
    };
  };
}
