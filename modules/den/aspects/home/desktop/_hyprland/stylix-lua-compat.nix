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
  # Stylix's Hyprland target still cannot be used in Lua mode, but no longer for
  # the reason this comment used to give. Stylix now branches on
  # `wayland.windowManager.hyprland.configType` and puts its colors under
  # `config` on its own (stylix modules/hyprland/hm.nix), so the old complaint —
  # top-level keys rendering as hl.general(...) — is fixed upstream.
  #
  # What is left is the key *form*. Stylix emits the flat, dotted names:
  #
  #     ["general"] = { ["col.active_border"] = "rgb(...)" }
  #
  # Those are hyprlang variable names, and they are real — Hyprland's own Lua
  # stub lists them, but as fields of HL.ConfigValueTypes, the flat namespace
  # that hl.get/keyword-style lookups use. The table handed to hl.config({}) is
  # a different type: HL.ConfigOpt.General declares `col` as a nested
  # HL.ConfigOpt.General.Col, with active_border inside it. There is no field
  # named "col.active_border" on it at all.
  #
  # So the nesting below is not a stylistic preference, it is the shape the Lua
  # API actually declares (verified against
  # hyprland-0.56.2/share/hypr/stubs/hl.meta.lua). Re-check that stub before
  # dropping this — if stylix ever emits nested `col`, the whole file goes.
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
