# zoxide. Program split into a named module for wrapping; the impermanence
# persist entry (a cosmos option absent in an isolated wrap eval) stays in
# `common`.
{config, ...}: {
  flake.modules.homeManager.zoxide = {config, ...}: {
    programs.zoxide = {
      enable = true;
      enableZshIntegration = config.programs.zsh.enable;
      options = [
        "--cmd cd"
      ];
    };
  };

  flake.modules.homeManager.common = {
    imports = [config.flake.modules.homeManager.zoxide];
    cosmos.system.impermanence.persist.directories = [".local/share/zoxide"];
  };
}
