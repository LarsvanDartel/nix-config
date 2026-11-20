# kanidm — patch: an OAuth2 refresh treats an expired parent session as revoked, so clients get invalid_grant and reprompt instead of dead tokens.
{...}: {
  nixpkgs.overlays = [
    (_final: prev: {
      kanidmWithSecretProvisioning_1_12 =
        prev.lib.warnIf (prev.kanidmWithSecretProvisioning_1_12.version != "1.12.1") ''
          modules/pkgs/kanidm-expired-parent-session.nix: nixpkgs' kanidm is now ${prev.kanidmWithSecretProvisioning_1_12.version}.
          Check whether check_oauth2_account_uuid_valid (server/lib/src/idm/server.rs) still accepts an expired parent session; drop the patch or bump this guard.
        ''
        (prev.kanidmWithSecretProvisioning_1_12.overrideAttrs (old: {
          patches = (old.patches or []) ++ [./_kanidm/expired-parent-session.patch];
        }));
    })
  ];
}
