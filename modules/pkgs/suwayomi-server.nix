# suwayomi-server pinned ahead of nixpkgs — a version floor, not a
# preference: keiyoushi moved to Mihon's Extension Store (extension API v1.6,
# readable only by Suwayomi >= 2.3.2223; nixpkgs has 2.1.1867 as of
# 2026-08-19), so on 2.1 the extensions page renders a two-entry tombstone.
# Cheap to carry: upstream's fat jar means this overrides two strings. Drop
# once `nix eval nixpkgs#suwayomi-server.version` catches up.
#
# One-way upgrade: 2.3 rewrites the H2 database in place and extension repos
# may not survive (the library does). /persist/var/lib/suwayomi-server is in
# restic's paths (services/restic.nix) — the undo; the downloads dir next to
# it is re-fetchable and deliberately excluded.
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
