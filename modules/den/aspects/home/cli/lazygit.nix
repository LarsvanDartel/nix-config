# home.lazygit — lazygit git TUI
{...}: {
  den.aspects.home.lazygit.homeManager = {...}: {
    programs.lazygit = {
      enable = true;
      settings = {
        disableStartupPopups = true;
        gui.skipDiscardChangeWarning = true;
      };
    };
  };
}
