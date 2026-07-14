# mpv. Split into its own named module so it can be wrapped as a portable,
# stylix-themed package; the `desktop` aggregate just imports it.
{config, ...}: let
  inherit (config.flake.modules.homeManager) mpv;
in {
  flake.modules.homeManager.mpv = {...}: {
    programs.mpv.enable = true;
  };

  flake.modules.homeManager.desktop.imports = [mpv];
}
