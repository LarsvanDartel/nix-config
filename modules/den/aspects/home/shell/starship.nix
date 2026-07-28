# home.starship
{...}: {
  den.aspects.home.starship.homeManager = {config, ...}: {
    programs.starship = {
      enable = true;
      enableZshIntegration = config.programs.zsh.enable;
      settings = {};
    };
  };
}
