# stalwart_1 pinned ahead of nixos-unstable: 1.1.1 from the nixpkgs master
# merge of PR #582349, which also renamed stalwart_1_0 (1.0.0) to stalwart_1.
# The pinned build is in cache.nixos.org. Inert, and warns, once nixpkgs
# ships stalwart_1 itself; then delete this file and its input.
{inputs, ...}: {
  flake-file.inputs.nixpkgs-stalwart-pin.url = "github:nixos/nixpkgs/8370dc40d6df4d236eeaf88f8ca03afbf57916c5";

  nixpkgs.overlays = [
    (_final: prev: {
      stalwart_1 =
        if prev ? stalwart_1
        then
          prev.lib.warn ''
            modules/pkgs/stalwart.nix: nixpkgs now ships stalwart_1 (${prev.stalwart_1.version}); delete the pin and its input.
          ''
          prev.stalwart_1
        else inputs.nixpkgs-stalwart-pin.legacyPackages.${prev.stdenv.hostPlatform.system}.stalwart_1;
    })
  ];
}
