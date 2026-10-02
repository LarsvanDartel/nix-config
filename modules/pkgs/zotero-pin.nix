# zotero fails against nixpkgs 2026-10-01 inside its own upstream
# Firefox-derived build tooling — a script patching `AboutTranslations`
# support out of `ActorManagerParent.sys.mjs` expects specific text that
# isn't there anymore ("AboutTranslations: \{ and ^  }, not found ...
# aborting"). That's Zotero's own vendored Gecko build machinery hitting a
# real upstream source change, not a nixpkgs packaging slip or something
# fixable with a flag — needs tracing into Zotero's build scripts for a
# real fix, out of scope for unblocking today's fleet lock bump.
#
# Pinned to the last nixpkgs revision zotero built clean on (what every host
# was running before this bump), same shape as nixpkgs-stable/-unstable in
# modules/meta/nixpkgs.nix. Drop once nixpkgs' zotero expression (or
# upstream Zotero) is fixed for newer nixpkgs.
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
