# home.clipse (clipboard manager; hyprland depends on it)
{...}: {
  den.aspects.home.clipse.homeManager = {...}: {
    cosmos.system.impermanence.persist.files = [".config/clipse/clipboard_history.json"];
    services.clipse.enable = true;
  };
}
