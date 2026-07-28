# home.hyprland.hyprshot — screenshot tool.
{...}: {
  den.aspects.home.hyprland.hyprshot.homeManager = {...}: {
    programs.hyprshot = {
      enable = true;
      saveLocation = "~/screenshots";
    };
  };
}
