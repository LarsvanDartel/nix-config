# zotero pinned to the last nixpkgs it built on: against nixpkgs 2026-10-01
# its vendored Gecko build script fails patching AboutTranslations out of
# ActorManagerParent.sys.mjs. Drop once nixpkgs' zotero builds again.
{inputs, ...}: {
  flake-file.inputs.nixpkgs-zotero-pin.url = "github:nixos/nixpkgs/4533d9293756b63904b7238acb84ac8fe4c8c2c4";

  nixpkgs.overlays = [
    (_final: _prev: {
      zotero =
        (import inputs.nixpkgs-zotero-pin {
          system = "x86_64-linux";
          config.allowUnfree = true;
        }).zotero;
    })
  ];
}
