# suwayomi-server — pinned ahead of nixpkgs, because the packaged version can
# no longer see any extensions at all.
#
# nixpkgs ships 2.1.1867 on both stable and unstable (checked 2026-08-19;
# upstream's newest is 2.3.2243, released 2026-07-13). That gap is not cosmetic:
#
#   * keiyoushi migrated to Mihon's Extension Store, extension API v1.6. The old
#     flat-array `repo/index.min.json` that 2.1 knows how to read is now a
#     two-entry tombstone — literally just "Outdated App" and "Update to Mihon
#     0.20.1+", which is exactly what the Browse → Extensions page renders. The
#     catalogue is not missing, it is being served a sign that says go away.
#   * Suwayomi gained v1.6 support and the Extension Store in 2.3.2223. There is
#     no configuration that makes 2.1 read the new format, so this is a version
#     floor rather than a preference.
#
# Cheap to carry: upstream publishes a fat jar and the nixpkgs derivation is a
# fetchurl plus makeWrapper, so this overrides two strings and builds nothing.
# Drop it the moment nixpkgs catches up — `nix eval nixpkgs#suwayomi-server.version`
# is the whole test.
#
# Upgrading past 2.1 is a one-way trip for the data directory: 2.3 moves to a
# newer H2 engine and rewrites the database in place, and the release notes warn
# that extension repos may not survive the migration to Extension Stores. The
# library itself is what matters and it does survive — but /var/lib/suwayomi-server
# is not in restic's paths, so there is no undo unless one is taken by hand.
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
