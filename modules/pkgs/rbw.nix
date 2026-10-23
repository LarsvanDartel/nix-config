# rbw — send `encryptedFor` on cipher writes; vaultwarden 2026.6 answers 422 without it.
# Warns once nixpkgs moves rbw off 1.15.0: check for the field, then drop or bump.
{...}: {
  nixpkgs.overlays = [
    (_final: prev: {
      rbw =
        prev.lib.warnIf (prev.rbw.version != "1.15.0") ''
          modules/pkgs/rbw.nix: nixpkgs' rbw is now ${prev.rbw.version}.
          Check whether it sends encryptedFor on cipher writes; delete the override or bump this guard.
        '' (prev.rbw.overrideAttrs (old: {
          patches = (old.patches or []) ++ [./_rbw/encrypted-for.patch];
        }));
    })
  ];
}
