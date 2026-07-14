# lazygit. Standalone named module for wrapping; `common` imports it.
{config, ...}: {
  flake.modules.homeManager.lazygit = {...}: {
    programs.lazygit = {
      enable = true;
      settings = {
        disableStartupPopups = true;
        gui.skipDiscardChangeWarning = true;
      };
    };
  };

  flake.modules.homeManager.common.imports = [config.flake.modules.homeManager.lazygit];
}
