# rbw — patched for vaultwarden (`encryptedFor` on cipher writes, rotated refresh tokens kept) and capitalised `-`-joined diceware with digits.
{...}: {
  nixpkgs.overlays = [
    (_final: prev: {
      rbw =
        prev.lib.warnIf (prev.rbw.version != "1.15.0") ''
          modules/pkgs/rbw.nix: nixpkgs' rbw is now ${prev.rbw.version}.
          Drop _rbw/rotated-refresh-token.patch if doy/rbw#378 is in it, and re-check vaultwarden-2026.patch still applies and is needed; then bump this guard.
        ''
        (prev.rbw.overrideAttrs (old: {
          # Without the refresh-token patch, rbw replays its login token and stops syncing once vaultwarden's 30-day expiry passes.
          patches =
            (old.patches or [])
            ++ [
              ./_rbw/vaultwarden-2026.patch
              ./_rbw/rotated-refresh-token.patch
            ];
        }));
    })
  ];
}
