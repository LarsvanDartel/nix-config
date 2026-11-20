# home.niri — user-side companion to desktop.niri, whose wrapped package bakes in niri's config.
{
  den,
  cosmosStyling,
  ...
}: {
  den.aspects.home.niri = {
    includes = [den.aspects.home.noctalia];

    homeManager = import ../../desktop/_niri/home.nix {inherit cosmosStyling;};
  };
}
