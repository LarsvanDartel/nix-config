# Stylix-based theming (home). Implementation, fonts, icons and themes live
# under ./_impl (import-tree ignores `_` paths).
{...}: {
  flake.modules.homeManager.desktop = ./_impl;
}
