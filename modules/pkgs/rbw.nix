# rbw — two local patches (vaultwarden-2026.patch):
#  - send `encryptedFor` on cipher writes; vaultwarden 2026.6 answers 422 without it.
#    Drop once rbw ships the field upstream.
#  - `generate --diceware` emits Capitalised-Words-joined-by-dashes plus a digit pair
#    instead of lowercase words separated by spaces, which most sites reject.
{...}: {
  nixpkgs.overlays = [
    (_final: prev: {
      rbw = prev.rbw.overrideAttrs (old: {
        patches = (old.patches or []) ++ [./_rbw/vaultwarden-2026.patch];
      });
    })
  ];
}
