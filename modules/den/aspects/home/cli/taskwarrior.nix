# home.taskwarrior (+ taskwarrior-tui)
{...}: {
  den.aspects.home.taskwarrior.homeManager = {
    pkgs,
    lib,
    ...
  }: let
    inherit (lib.meta) getExe;
  in {
    cosmos = {
      system.impermanence.persist.directories = [".local/share/task"];
      cli.shells.zsh.aliases.tt = "taskwarrior-tui";
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
