# rbw — patched (vaultwarden-2026.patch) to send `encryptedFor` on cipher writes (else 422) and emit lowercase space-separated diceware.
{...}: {
  nixpkgs.overlays = [
    (_final: prev: {
      rbw = prev.rbw.overrideAttrs (old: {
        patches = (old.patches or []) ++ [./_rbw/vaultwarden-2026.patch];
      });
    })
  ];
}
