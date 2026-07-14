{...}: {
  flake.modules.homeManager.starship = {config, ...}: {
    programs.starship = {
      enable = true;
      enableZshIntegration = config.programs.zsh.enable;
      settings = {};
    };
  };
}
