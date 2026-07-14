{...}: {
  flake.modules.homeManager.common = {
    config,
    lib,
    ...
  }: let
    inherit (lib.modules) mkDefault;
  in {
    programs.eza = {
      enable = true;
      enableZshIntegration = config.programs.zsh.enable;
      colors = "auto";
      extraOptions = [
        "--group-directories-first"
        "--time-style=long-iso"
        "--header"
      ];
      git = mkDefault config.programs.git.enable;
      icons = "auto";
    };
  };
}
