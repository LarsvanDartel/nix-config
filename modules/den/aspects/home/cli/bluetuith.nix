# home.bluetuith — bluetuith Bluetooth TUI with a desktop entry
{...}: {
  den.aspects.home.bluetuith.homeManager = {pkgs, ...}: {
    home.packages = with pkgs; [bluetuith];

    xdg.desktopEntries.bluetuith = {
      exec = "${pkgs.bluetuith}/bin/bluetuith";
      name = "Bluetuith";
      terminal = true;
      type = "Application";
    };
  };
}
