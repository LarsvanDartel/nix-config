# suwayomi-server — version floor ahead of nixpkgs for keiyoushi's store (>= 2.3.2223); 2.3 rewrites the H2 database one way, restic is the undo.
{...}: {
  nixpkgs.overlays = [
    (_final: prev: let
      version = "2.3.2243";
    in {
      suwayomi-server =
        if prev.lib.versionAtLeast prev.suwayomi-server.version version
        then
          prev.lib.warn ''
            modules/pkgs/suwayomi-server.nix: nixpkgs' suwayomi-server is now ${prev.suwayomi-server.version} (>= ${version}); delete the override.
          ''
          prev.suwayomi-server
        else
          prev.suwayomi-server.overrideAttrs (old: {
            inherit version;

            src = prev.fetchurl {
              url = "https://github.com/Suwayomi/Suwayomi-Server/releases/download/v${version}/Suwayomi-Server-v${version}.jar";
              hash = "sha256-ghFBsy4XDUoC08vf7Vd+2PB70iOD/19BMuu1rkDpjdU=";
            };

            meta = old.meta // {changelog = "https://github.com/Suwayomi/Suwayomi-Server/releases/tag/v${version}";};
          });
    })
  ];
}
