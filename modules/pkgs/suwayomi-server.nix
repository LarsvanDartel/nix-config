# suwayomi-server pinned ahead of nixpkgs — a version floor: keiyoushi's
# extension store needs Suwayomi >= 2.3.2223 (nixpkgs had 2.1.1867). Drop
# once `nix eval nixpkgs#suwayomi-server.version` catches up.
# One-way upgrade: 2.3 rewrites the H2 database; restic backs up
# /persist/var/lib/suwayomi-server as the undo.
{...}: {
  nixpkgs.overlays = [
    (_final: prev: {
      suwayomi-server = prev.suwayomi-server.overrideAttrs (old: rec {
        version = "2.3.2243";

        src = prev.fetchurl {
          url = "https://github.com/Suwayomi/Suwayomi-Server/releases/download/v${version}/Suwayomi-Server-v${version}.jar";
          hash = "sha256-ghFBsy4XDUoC08vf7Vd+2PB70iOD/19BMuu1rkDpjdU=";
        };

        meta = old.meta // {changelog = "https://github.com/Suwayomi/Suwayomi-Server/releases/tag/v${version}";};
      });
    })
  ];
}
