# btop. Standalone named module so it can be wrapped as a portable, themed
# package; `common` imports it for deployment.
{config, ...}: {
  flake.modules.homeManager.btop = {...}: {
    programs.btop.enable = true;
  };

  flake.modules.homeManager.common.imports = [config.flake.modules.homeManager.btop];
}
