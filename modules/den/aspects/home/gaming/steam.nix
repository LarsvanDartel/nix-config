# home.steam — impermanence persist dirs for steam. Delivered to every user by
# roles.gaming, which enables the program at the nixos level.
{...}: {
  den.aspects.home.steam.homeManager = {...}: {
    cosmos.system.impermanence.persist.directories = [
      ".local/share/Steam"
      ".config/unity3d"
      ".local/share/applications"
      # Steam's desktop shortcuts point at steam_icon_<appid>.png in here; the
      # rest of .local/share/icons holds home-manager symlinks.
      ".local/share/icons/hicolor"
    ];
  };
}
