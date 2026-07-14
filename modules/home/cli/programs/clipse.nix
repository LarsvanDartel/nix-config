{...}: {
  flake.modules.homeManager.clipse = {...}: {
    cosmos.system.impermanence.persist.files = [".config/clipse/clipboard_history.json"];

    services.clipse.enable = true;
  };
}
