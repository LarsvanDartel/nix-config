{...}: {
  flake.modules.homeManager.common = {...}: {
    programs.btop.enable = true;
  };
}
