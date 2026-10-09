# FiniteSingularity's three OBS plugins (obs-advanced-masks,
# obs-composite-blur, obs-stroke-glow-shadow) share a const-discarding
# strrchr in src/obs-utils.c that nixpkgs 2026-10-01's GCC makes fatal under
# their -Werror; demote -Werror=discarded-qualifiers. Drop once upstream
# fixes it or nixpkgs moves past this GCC.
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
