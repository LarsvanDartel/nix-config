# home.hyprland — the Hyprland compositor. The core config lives in the _hyprland
# tree (settings/binds/animations/colors/rules); its addons (waybar, mako, rofi,
# hyprlock, hyprpaper, hyprshot) are sibling aspects under home.hyprland.*, all
# included here. Pulls in the clipse clipboard manager it depends on.
{den, ...}: {
  den.aspects.home.hyprland = {
    includes = with den.aspects.home; [
      clipse
      hyprland.waybar
      hyprland.mako
      hyprland.rofi
      hyprland.hyprlock
      hyprland.hyprpaper
      hyprland.hyprshot
    ];
    homeManager.imports = [./_hyprland];
  };
}
