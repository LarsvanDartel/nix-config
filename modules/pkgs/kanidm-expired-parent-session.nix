# kanidm: an OAuth2 refresh only rejects a revoked parent session, not an
# expired one still awaiting purge. The refresh then succeeds, its own write
# purges the parent, and the new tokens are dead on arrival: Thunderbird gets
# a 200, keeps the token until it expires, and IMAP/SMTP fail for up to
# 15 minutes without a login prompt. The patch treats an expired parent as
# revoked, so the refresh answers invalid_grant and Thunderbird prompts.
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
