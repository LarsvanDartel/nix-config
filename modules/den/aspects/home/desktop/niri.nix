# home.niri — user-side companion to desktop.niri. Deliberately almost empty:
# niri's config is baked into the wrapped package there (no config.kdl in
# $HOME); this only pulls the shell and user-scoped bits the binds assume.
{den, ...}: {
  den.aspects.home.niri = {
    includes = [den.aspects.home.noctalia];

    homeManager = import ../../desktop/_niri/home.nix {};
  };
}
