{pkgs, ...}: {
  name = "Noto Color Emoji";
  package = pkgs.noto-fonts-color-emoji;
  recommendedSize = 12;
  fallbackFonts = [];
}
