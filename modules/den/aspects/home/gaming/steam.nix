# home.steam — impermanence persist dirs for steam (the program is enabled at
# the nixos level via roles.gaming).
{...}: {
  den.aspects.home.steam.homeManager = {...}: {
    cosmos.system.impermanence.persist.directories = [
      ".local/share/Steam"
      ".config/unity3d"
      ".local/share/applications"
    ];
  };
}
