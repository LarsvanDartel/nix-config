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
  # Stylix's Hyprland target stays off in Lua mode — not for the old reason
  # (the top-level-keys complaint is fixed upstream: stylix branches on
  # configType now), but the key *form*. Stylix emits the flat hyprlang names
  # ("col.active_border"), which exist only in the flat HL.ConfigValueTypes
  # namespace; the table handed to hl.config({}) is the nested HL.ConfigOpt.*
  # shape, which has no "col.active_border" field at all. The nesting below is
  # the shape the Lua API actually declares (verified against
  # hyprland-0.56.2's hl.meta.lua) — re-check that stub before dropping this;
  # if stylix ever emits nested `col`, the whole file goes.
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

      # Stylix themes this and we were silently dropping it: disabling the
      # target loses everything it sets, not just the parts that rendered
      # wrong, so shadows kept Hyprland's default black instead of base00.
      decoration.shadow.color = rgba colors.base00 "99";
    };
  };
}
