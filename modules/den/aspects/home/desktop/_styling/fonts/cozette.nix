# home.styling — the Cozette font family.
{pkgs, ...}: {
  name = "Cozette";
  package = pkgs.cozette;
  recommendedSize = 9;
  pixelGrid = 13;
  boldFamily = "CozetteVectorBold";
  fallbackFonts = [
    "Cozette Vector"
    "Symbols Nerd Font Mono"
  ];
}
