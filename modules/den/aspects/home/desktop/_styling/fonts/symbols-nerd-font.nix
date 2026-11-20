# home.styling — the Symbols Nerd Font Mono font family.
{pkgs, ...}: {
  name = "Symbols Nerd Font Mono";
  package = pkgs.nerd-fonts.symbols-only;
  recommendedSize = 12;
  fallbackFonts = [];
}
