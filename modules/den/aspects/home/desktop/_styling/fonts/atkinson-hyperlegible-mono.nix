# home.styling — the Atkinson Hyperlegible Mono font family, monospace companion to the Next sans.
{pkgs, ...}: {
  name = "Atkinson Hyperlegible Mono";
  package = pkgs.atkinson-hyperlegible-mono;
  recommendedSize = 10;
  fallbackFonts = ["Symbols Nerd Font Mono"];
}
