# zotero — pinned to the last nixpkgs it built on: newer ones fail its Gecko build or need the insecure firefox-esr-140-bin.
{inputs, ...}: {
  flake-file.inputs.nixpkgs-zotero-pin.url = "github:nixos/nixpkgs/4533d9293756b63904b7238acb84ac8fe4c8c2c4";

  nixpkgs.overlays = [
    (_final: prev: {
      zotero =
        prev.lib.warnIf (prev.zotero.version != "10.0.9") ''
          modules/pkgs/zotero-pin.nix: nixpkgs' zotero is now ${prev.zotero.version}.
          Check whether it builds; delete the pin and its input, or bump this guard.
        ''
        (import inputs.nixpkgs-zotero-pin {
          system = "x86_64-linux";
          config.allowUnfree = true;
        }).zotero;
    })
  ];
}
