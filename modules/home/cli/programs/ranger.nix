{...}: {
  flake.modules.homeManager.ranger = {...}: {
    programs.ranger = {
      enable = true;
    };
  };
}
