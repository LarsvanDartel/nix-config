{...}: {
  flake.modules.homeManager.desktop = {pkgs, ...}: {
    home.packages = with pkgs; [bluetuith];

    xdg.desktopEntries.bluetuith = {
      exec = "${pkgs.bluetuith}/bin/bluetuith";
      name = "Bluetuith";
      terminal = true;
      type = "Application";
    };
  };
}
