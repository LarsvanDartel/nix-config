{pkgs, ...}: {
  name = "Cozette";
  package = pkgs.cozette;
  recommendedSize = 9;
  fallbackFonts = ["Cozette Vector"];
}
