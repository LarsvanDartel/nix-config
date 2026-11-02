# zotero pinned to the last nixpkgs it built on: against nixpkgs 2026-10-01
# its vendored Gecko build script fails patching AboutTranslations out of
# ActorManagerParent.sys.mjs. nixpkgs' 10.0.6 runs on firefox-esr-140-bin,
# marked insecure (EOL), so it refuses to evaluate without permitting that.
# Warns once nixpkgs moves zotero off 10.0.6: check whether it builds, then
# drop the pin (and its input) or bump.
{inputs, ...}: {
  flake-file.inputs.nixpkgs-zotero-pin.url = "github:nixos/nixpkgs/4533d9293756b63904b7238acb84ac8fe4c8c2c4";

  nixpkgs.overlays = [
    (_final: prev: {
      zotero =
        prev.lib.warnIf (prev.zotero.version != "10.0.6") ''
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
