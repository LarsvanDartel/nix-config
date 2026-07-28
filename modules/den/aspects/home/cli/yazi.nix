# home.yazi (+ the defaultApplication option; deployment sets it true)
{...}: {
  den.aspects.home.yazi.homeManager = {
    config,
    lib,
    ...
  }: let
    inherit (lib.options) mkOption;
    inherit (lib.types) bool;
    inherit (lib.modules) mkIf;

    cfg = config.cosmos.cli.programs.yazi;
  in {
    options.cosmos.cli.programs.yazi.defaultApplication = mkOption {
      type = bool;
      default = false;
    };

    config = {
      programs.yazi = {
        enable = true;
        enableZshIntegration = config.programs.zsh.enable;
        shellWrapperName = "y";
      };
      xdg.mimeApps = mkIf cfg.defaultApplication {
        enable = true;
        defaultApplications."inode/directory" = ["yazi.desktop"];
      };
    };
  };
}
