# spotify-player: ncspot re-registered its Spotify app's redirect URI as
# http://127.0.0.1:8989/ncspot_login. 0.25.2 uses it for the fallback client,
# but a login with the default (ncspot) client_id still sends
# login_redirect_uri's /login and dies on "redirect_uri: Not matching
# configuration". Use NCSPOT_REDIRECT_URI there too; librespot's login
# (official client id) keeps /login. Upstream: aome510/spotify-player#1107.
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
