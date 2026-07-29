# home.niri — the user-side companion to desktop.niri.
#
# There is deliberately almost nothing here: niri's configuration is baked into
# the wrapped package by desktop.niri, so no config.kdl is written to $HOME.
# This aspect only pulls in the shell and the few user-scoped bits the binds
# assume exist.
{den, ...}: {
  den.aspects.home.niri = {
    includes = [den.aspects.home.noctalia];

    homeManager = import ../../desktop/_niri/home.nix {};
  };
}
