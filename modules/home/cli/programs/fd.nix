# fd. Standalone named module for wrapping; `common` imports it.
{config, ...}: {
  flake.modules.homeManager.fd = {...}: {
    programs.fd = {
      enable = true;
    };
  };

  flake.modules.homeManager.common.imports = [config.flake.modules.homeManager.fd];
}
