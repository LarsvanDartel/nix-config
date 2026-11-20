# stalwart_1 — pinned ahead of nixos-unstable to 1.1.1 from nixpkgs master (PR #582349); delete with its input once nixpkgs ships it.
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
