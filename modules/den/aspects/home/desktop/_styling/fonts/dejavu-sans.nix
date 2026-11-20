# home.styling — the DejaVu Sans font family.
{pkgs, ...}: {
  name = "DejaVu Sans";
  package = pkgs.dejavu_fonts;
  recommendedSize = 12;
  fallbackFonts = [];
}
