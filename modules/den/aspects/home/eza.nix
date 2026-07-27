# home.eza
{...}: {
  den.aspects.home.eza.homeManager = {
    config,
    lib,
    ...
  }: {
    programs.eza = {
      enable = true;
      enableZshIntegration = config.programs.zsh.enable;
      colors = "auto";
      extraOptions = [
        "--group-directories-first"
        "--time-style=long-iso"
        "--header"
      ];
      git = lib.mkDefault config.programs.git.enable;
      icons = "auto";
    };
  };
}
