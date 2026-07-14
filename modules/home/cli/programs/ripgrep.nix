# ripgrep. Standalone named module for wrapping; `common` imports it.
{config, ...}: {
  flake.modules.homeManager.ripgrep = {...}: {
    programs.ripgrep = {
      enable = true;
      arguments = [
        "--colors=line:style:bold"
        "--hidden"
        "--line-number"
        "--no-heading"
        "--color=always"
        "--smart-case"
        "--glob=!*.{jpg,jpeg,png,gif,svg}"
      ];
    };
  };

  flake.modules.homeManager.common.imports = [config.flake.modules.homeManager.ripgrep];
}
