# home.niri — user-side companion to desktop.niri. Almost empty: niri's config
# is baked into the wrapped package there (no config.kdl in $HOME).
{den, ...}: {
  den.aspects.home.niri = {
    includes = [den.aspects.home.noctalia];

    homeManager = import ../../desktop/_niri/home.nix {};
  };
}
