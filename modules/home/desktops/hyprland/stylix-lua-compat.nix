{
  config,
  lib,
  ...
}: let
  inherit (lib.modules) mkIf;

  colors = config.lib.stylix.colors;
  rgb = color: "rgb(${color})";
in {
  # Stylix's Hyprland target sets settings.{general,decoration,group,misc} as top-level
  # keys. In Lua mode these render as hl.general(...) etc. — functions that don't exist
  # in the Hyprland Lua API. Disabling the target suppresses those calls; we replicate
  # the color settings below under settings.config.* where they are emitted via the
  # single valid hl.config({}) call.
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
    };
  };
}
