# home.steam — per-user Steam state; roles.gaming enables the program system-wide.
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
