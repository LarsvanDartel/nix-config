{...}: {
  flake.modules.homeManager.common = {...}: {
    programs.fd = {
      enable = true;
    };
  };
}
