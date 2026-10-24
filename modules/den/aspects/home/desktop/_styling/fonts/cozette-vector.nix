{pkgs, ...}: {
  name = "Cozette Vector";
  package = pkgs.cozette;
  recommendedSize = 9;
  pixelGrid = 13;
  boldFamily = "CozetteVectorBold";
  fallbackFonts = ["Symbols Nerd Font Mono"];
}
