# eza. Standalone named module for wrapping; `common` imports it. (The zsh/git
# integration reads the merged home config — enabled in deployment, off in an
# isolated wrapper.)
{config, ...}: {
  flake.modules.homeManager.eza = {
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

  flake.modules.homeManager.common.imports = [config.flake.modules.homeManager.eza];
}
