# wrappers — nix-wrapper-modules, the library wrapped programs are built with; see docs/src/conventions.md#code.
{...}: {
  flake-file.inputs.nix-wrapper-modules = {
    url = "github:nix-community/nix-wrapper-modules";
    inputs.nixpkgs.follows = "nixpkgs";
  };
}
