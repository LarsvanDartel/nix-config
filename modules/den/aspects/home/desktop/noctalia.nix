# home.noctalia — the noctalia v5 shell through home-manager's `programs.noctalia`.
# Body in ./_noctalia/home.nix, a plain module imported by this aspect.
{inputs, ...}: {
  # Public HTTPS like home.wallpapers: build-gate has no SSH credential.
  flake-file.inputs.noctalia-netbird = {
    url = "git+https://knot.lvdar.nl/did:plc:cqv2kfof3l53jrrzj553e6fb?shallow=1";
    flake = false;
  };

  den.aspects.home.noctalia.homeManager = import ./_noctalia/home.nix {inherit inputs;};
}
