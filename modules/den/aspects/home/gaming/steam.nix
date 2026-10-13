# home.steam — impermanence persist dirs for steam. Delivered to every user by
# roles.gaming, which enables the program at the nixos level.
{...}: {
  den.aspects.home.steam.homeManager = {...}: {
    cosmos.system.impermanence.persist.directories = [
      ".local/share/Steam"
      ".config/unity3d"
      ".local/share/applications"
    ];
  };
}
