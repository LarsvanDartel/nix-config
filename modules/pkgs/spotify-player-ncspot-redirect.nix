# spotify-player: ncspot re-registered its Spotify app's redirect URI as
# http://127.0.0.1:8989/ncspot_login, so 0.25.1's Web API login with the
# default (ncspot) client_id dies on "redirect_uri: Not matching
# configuration". Use that URI for every ncspot-client flow; librespot's
# login (official client id) keeps login_redirect_uri's /login. Upstream:
# aome510/spotify-player#1107 (#1108 only fixes the fallback path).
{...}: {
  nixpkgs.overlays = [
    (_final: prev: {
      spotify-player =
        prev.lib.warnIf (prev.spotify-player.version != "0.25.1") ''
          modules/pkgs/spotify-player-ncspot-redirect.nix: nixpkgs' spotify-player is now ${prev.spotify-player.version}.
          Check whether ncspot-client logins use /ncspot_login upstream (aome510/spotify-player#1107); delete the override or bump this guard.
        ''
        (prev.spotify-player.overrideAttrs (old: {
          postPatch =
            (old.postPatch or "")
            + ''
              substituteInPlace spotify_player/src/auth.rs --replace-fail \
                'NCSPOT_REDIRECT_URI: &str = "http://127.0.0.1:8989/login"' \
                'NCSPOT_REDIRECT_URI: &str = "http://127.0.0.1:8989/ncspot_login"'
              substituteInPlace spotify_player/src/client/mod.rs --replace-fail \
                $'build_oauth(configs.app_config.login_redirect_uri.clone()),\n            config,' \
                $'build_oauth(auth::NCSPOT_REDIRECT_URI.to_string()),\n            config,'
            '';
        }));
    })
  ];
}
