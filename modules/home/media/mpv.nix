{...}: {
  flake.modules.homeManager.desktop = {...}: {
    programs.mpv.enable = true;
  };
}
