# home.zoxide (+ its impermanence persist entry)
{...}: {
  den.aspects.home.zoxide.homeManager = {config, ...}: {
    cosmos.system.impermanence.persist.directories = [".local/share/zoxide"];
    programs.zoxide = {
      enable = true;
      enableZshIntegration = config.programs.zsh.enable;
      options = ["--cmd cd"];
    };
  };
}
