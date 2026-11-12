# Atkinson Hyperlegible Mono — monospace companion to Atkinson Hyperlegible Next.
{pkgs, ...}: {
  name = "Atkinson Hyperlegible Mono";
  package = pkgs.atkinson-hyperlegible-mono;
  recommendedSize = 10;
  fallbackFonts = ["Symbols Nerd Font Mono"];
}
