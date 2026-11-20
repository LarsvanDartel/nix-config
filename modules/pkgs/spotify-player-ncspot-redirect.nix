# spotify-player — default (ncspot) client_id logins use NCSPOT_REDIRECT_URI, matching ncspot's registered redirect (aome510/spotify-player#1107).
{...}: {
  nixpkgs.overlays = [
    (_final: prev: {
      spotify-player =
        prev.lib.warnIf (prev.spotify-player.version != "0.25.2") ''
          modules/pkgs/spotify-player-ncspot-redirect.nix: nixpkgs' spotify-player is now ${prev.spotify-player.version}.
          Check whether ncspot-client logins use /ncspot_login upstream (aome510/spotify-player#1107); delete the override or bump this guard.
        ''
        (prev.spotify-player.overrideAttrs (old: {
          postPatch =
            (old.postPatch or "")
            + ''
              substituteInPlace spotify_player/src/client/mod.rs --replace-fail \
                $'build_oauth(configs.app_config.login_redirect_uri.clone()),\n            config,' \
                $'build_oauth(auth::NCSPOT_REDIRECT_URI.to_string()),\n            config,'
            '';
        }));
    })
  ];
}
