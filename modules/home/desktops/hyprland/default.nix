# Hyprland (home). Implementation and its addons/parts live under ./_impl
# (import-tree ignores `_` paths). Pulls in the clipse clipboard manager it
# depends on.
{config, ...}: let
  inherit (config.flake.modules.homeManager) clipse;
in {
  flake.modules.homeManager.hyprland = {
    imports = [clipse ./_impl];
  };
}
