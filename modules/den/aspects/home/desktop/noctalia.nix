# home.noctalia — the noctalia shell as one compositor-agnostic, wrapped package.
# Body in ./_noctalia/home.nix so voyager's `specialisation.niri` can reuse it.
{inputs, ...}: {
  den.aspects.home.noctalia.homeManager = import ./_noctalia/home.nix {inherit inputs;};
}
