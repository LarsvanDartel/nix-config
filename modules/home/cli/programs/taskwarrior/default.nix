{
  config,
  lib,
  pkgs,
  ...
}: let
  inherit (lib.options) mkEnableOption;
  inherit (lib.modules) mkIf;
  inherit (lib.meta) getExe;

  cfg = config.cosmos.cli.programs.taskwarrior;
in {
  options.cosmos.cli.programs.taskwarrior = {
    enable = mkEnableOption "taskwarrior";
  };

  config = mkIf cfg.enable {
    cosmos = {
      system.impermanence.persist.directories = [".local/share/task"];
      cli.shells.zsh.aliases = {
        tt = "taskwarrior-tui";
      };
    };

    programs.taskwarrior = {
      enable = true;
      package = pkgs.taskwarrior3;
    };

    home.packages = [pkgs.taskwarrior-tui];

    xdg.desktopEntries.taskwarrior-tui = {
      exec = getExe pkgs.taskwarrior-tui;
      name = "Taskwarrior";
      terminal = true;
      type = "Application";
    };
  };
}
