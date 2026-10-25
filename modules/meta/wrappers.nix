# wrappers — nix-wrapper-modules, the library wrapped programs are built
# with. A wrapped program's aspect owns `mk<prog> = pkgs: …wrap {…}`, exports
# it as `packages.<system>.<prog>` and has home-manager install that same
# wrapper: the wrapper is the config's source of truth, so home-manager must
# not also write one for it.
{...}: {
  flake-file.inputs.nix-wrapper-modules = {
    url = "github:nix-community/nix-wrapper-modules";
    inputs.nixpkgs.follows = "nixpkgs";
  };
}
