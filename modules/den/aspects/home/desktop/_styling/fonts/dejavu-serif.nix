# home.styling — the DejaVu Serif font family.
{pkgs, ...}: {
  name = "DejaVu Serif";
  package = pkgs.dejavu_fonts;
  recommendedSize = 12;
  fallbackFonts = [];
}
