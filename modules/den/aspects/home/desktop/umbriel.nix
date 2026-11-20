# home.umbriel — user-side companion to desktop.umbriel; body in ./_umbriel/home.nix.
{
  den,
  cosmosStyling,
  ...
}: {
  den.aspects.home.umbriel = {
    includes = [den.aspects.home.noctalia];

    homeManager = import ./_umbriel/home.nix {inherit cosmosStyling;};
  };
}
