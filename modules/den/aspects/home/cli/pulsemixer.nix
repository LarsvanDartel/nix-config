# home.pulsemixer
{...}: {
  den.aspects.home.pulsemixer.homeManager = {pkgs, ...}: {
    home.packages = with pkgs; [pulsemixer];

    xdg.desktopEntries.pulsemixer = {
      name = "Pulsemixer";
      comment = "Pulsemixer is a simple ncurses mixer for PulseAudio";
      exec = "${pkgs.pulsemixer}/bin/pulsemixer";
      terminal = true;
      categories = ["AudioVideo" "Audio"];
    };
  };
}
