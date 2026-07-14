{...}: {
  flake.modules.homeManager.steam = {...}: {
    cosmos.system.impermanence.persist.directories = [
      ".local/share/Steam"
      ".config/unity3d"
      ".local/share/applications"
    ];
  };
}
