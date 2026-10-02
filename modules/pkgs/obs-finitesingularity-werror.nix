# FiniteSingularity's three OBS plugins (obs-advanced-masks,
# obs-composite-blur, obs-stroke-glow-shadow) all vendor a copy-pasted
# `src/obs-utils.c` with the same const-correctness slip:
#
#   char *pos = strrchr(file_name, '/');   // file_name is `const char *`
#
# Their own CMakeLists enables -Werror, and nixpkgs 2026-10-01's GCC now
# flags the implicit const-qualifier discard as an error instead of a
# warning:
#
#   src/obs-utils.c:NNN: error: initialization discards 'const' qualifier
#   from pointer target type [-Werror=discarded-qualifiers]
#
# Not ours to patch (upstream's own source, same bug copy-pasted three
# times), not worth carrying three patches for one diagnostic — downgrade
# just this one warning back to non-fatal via NIX_CFLAGS_COMPILE, same
# shape as obs-move-transition.nix's -Werror=deprecated-declarations fix.
# Drop once upstream fixes the qualifier or nixpkgs bumps past this GCC.
{...}: {
  nixpkgs.overlays = [
    (_final: prev: let
      fixWerror = pkg:
        pkg.overrideAttrs (old: {
          NIX_CFLAGS_COMPILE =
            (old.NIX_CFLAGS_COMPILE or "")
            + " -Wno-error=discarded-qualifiers";
        });
    in {
      obs-studio-plugins =
        prev.obs-studio-plugins
        // {
          obs-advanced-masks = fixWerror prev.obs-studio-plugins.obs-advanced-masks;
          obs-composite-blur = fixWerror prev.obs-studio-plugins.obs-composite-blur;
          obs-stroke-glow-shadow = fixWerror prev.obs-studio-plugins.obs-stroke-glow-shadow;
        };
    })
  ];
}
