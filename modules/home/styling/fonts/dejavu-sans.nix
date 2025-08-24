{pkgs, ...}: {
  name = "DejaVu Sans";
  package = pkgs.dejavu_fonts;
  recommendedSize = 12;
  fallbackFonts = [];
}
