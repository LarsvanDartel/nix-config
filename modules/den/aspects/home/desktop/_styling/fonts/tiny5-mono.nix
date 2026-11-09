# Tiny5 Mono — 5-pixel monospace font; 128 of its 1024 units per pixel, so the grid is 8px.
{pkgs, ...}: {
  name = "Tiny5 Mono";
  package = pkgs.tiny5-mono;
  recommendedSize = 12;
  pixelGrid = 8;
  # No pixel-exact bold exists (pkgs/tiny5-mono.nix): bold gets the regular cut, not a smeared synthetic one.
  boldFamily = "Tiny5 Mono";
  fallbackFonts = ["Symbols Nerd Font Mono"];
}
