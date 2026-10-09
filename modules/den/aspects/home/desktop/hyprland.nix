# home.hyprland — the Hyprland compositor. Core config in ./_hyprland; addons
# are sibling aspects.
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
