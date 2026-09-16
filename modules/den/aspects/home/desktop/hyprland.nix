# home.hyprland — the Hyprland compositor. Core config in ./_hyprland; addons
# (waybar, mako, rofi, hyprlock, hyprpaper, hyprshot) are sibling aspects,
# included here along with the clipse clipboard manager it depends on.
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
