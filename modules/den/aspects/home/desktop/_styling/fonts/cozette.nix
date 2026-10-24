{pkgs, ...}: {
  name = "Cozette";
  package = pkgs.cozette;
  recommendedSize = 9;
  pixelGrid = 13;
  fallbackFonts = [
    "Cozette Vector"
    "Symbols Nerd Font Mono"
  ];
}
