# rust system libs: nixpkgs' cargo setup hook forces system libraries since
# f4a03c0 (2026-11-07; AWS_LC_SYS_USE_SYSTEM=1, ZSTD_SYS_USE_PKG_CONFIG=1, a
# sentinel JEMALLOC_OVERRIDE, …; nixpkgs#570938), and these packages failed to
# build at that rev until their recipes caught up on master. Backports those
# recipe changes: aws-lc, jemalloc, sqlite and zstd as system libs found through
# pkg-config. stalwart_1_0 also loses OPENSSL_DIR/OPENSSL_LIB_DIR: aws-lc-sys
# takes them as its only candidates and never reaches pkg-config.
# Warns per package once nixpkgs ships the fix: then delete that entry.
{...}: {
  nixpkgs.overlays = [
    (final: prev: let
      backport = name: marker: f: let
        pkg = prev.${name};
      in
        prev.lib.warnIf (builtins.any (d: (d.pname or "") == marker) (pkg.buildInputs or [])) ''
          modules/pkgs/rust-system-libs.nix: nixpkgs' ${name} now lists ${marker} in buildInputs.
          Delete its entry from this override (the file once all are covered).
        ''
        (pkg.overrideAttrs (old:
          {
            nativeBuildInputs = (old.nativeBuildInputs or []) ++ [final.pkg-config];
          }
          // f old));
    in {
      stalwart_1_0 = backport "stalwart_1_0" "aws-lc" (old: {
        env = removeAttrs old.env ["OPENSSL_DIR" "OPENSSL_LIB_DIR"];
        buildInputs = old.buildInputs ++ [final.aws-lc final.rust-jemalloc-sys-unprefixed];
      });
      stalwart-cli = backport "stalwart-cli" "aws-lc" (old: {
        buildInputs = (old.buildInputs or []) ++ [final.aws-lc];
      });
      microbin = backport "microbin" "zstd" (old: {
        buildInputs = old.buildInputs ++ [final.sqlite final.zstd];
      });
      taskchampion-sync-server = backport "taskchampion-sync-server" "zstd" (old: {
        buildInputs = (old.buildInputs or []) ++ [final.sqlite final.zstd];
      });
      # Also needs taskwarrior's own fix to link SQLite through its CMake/Rust
      # bridge (GothenburgBitFactory/taskwarrior#4223).
      taskwarrior3 = backport "taskwarrior3" "sqlite" (old: {
        patches =
          (old.patches or [])
          ++ [
            (final.fetchpatch {
              url = "https://github.com/GothenburgBitFactory/taskwarrior/commit/bd86de7a6e99b1bc8d1a8f5704a08571afd2cdef.patch";
              hash = "sha256-6IAQlY5bExL9oCswIfs9D3MrcZKtQcSoNrEnAL46VXA=";
            })
          ];
        buildInputs = old.buildInputs ++ [final.sqlite];
      });
    })
  ];
}
