# yazi. Standalone named module for wrapping; `common` imports it. The
# defaultApplication option is declared here (defaults off, so an isolated wrap
# has no mimeApps); the deployment value is set in home/profiles/common.nix.
{config, ...}: {
  flake.modules.homeManager.yazi = {
    config,
    lib,
    ...
  }: let
    inherit (lib.options) mkOption;
    inherit (lib.types) bool;
    inherit (lib.modules) mkIf;

    cfg = config.cosmos.cli.programs.yazi;
  in {
    options.cosmos.cli.programs.yazi = {
      defaultApplication = mkOption {
        type = bool;
        default = false;
      };
    };

    config = {
      programs.yazi = {
        enable = true;
        enableZshIntegration = config.programs.zsh.enable;
        shellWrapperName = "y";
      };
      xdg.mimeApps = mkIf cfg.defaultApplication {
        enable = true;
        defaultApplications = {
          "inode/directory" = ["yazi.desktop"];
        };
      };
    };
  };

  flake.modules.homeManager.common.imports = [config.flake.modules.homeManager.yazi];
}
