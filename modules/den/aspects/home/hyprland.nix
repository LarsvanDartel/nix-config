# home.hyprland — the Hyprland compositor config. Reuses the hyprland _impl tree
# (import-tree-ignored) and pulls in the clipse clipboard manager it depends on.
{den, ...}: {
  den.aspects.home.hyprland = {
    includes = [den.aspects.home.clipse];
    homeManager.imports = [../../../home/desktops/hyprland/_impl];
  };
}
