# home.lazygit
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
