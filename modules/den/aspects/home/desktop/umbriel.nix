# home.umbriel — user-side companion to desktop.umbriel: config.toml and the session's rotation, gesture and tablet-mode units, body in ./_umbriel/home.nix.
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
