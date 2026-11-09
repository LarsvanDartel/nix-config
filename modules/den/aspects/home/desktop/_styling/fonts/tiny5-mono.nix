# Tiny5 Mono — 5-pixel monospace font; 128 of its 1024 units per pixel, so the grid is 8px.
{pkgs, ...}: {
  name = "Tiny5 Mono";
  package = pkgs.tiny5-mono;
  recommendedSize = 12;
  pixelGrid = 8;
  fallbackFonts = ["Symbols Nerd Font Mono"];
}
