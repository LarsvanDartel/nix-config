# FiniteSingularity's three OBS plugins (obs-advanced-masks,
# obs-composite-blur, obs-stroke-glow-shadow) share a const-discarding
# strrchr in src/obs-utils.c that nixpkgs 2026-10-01's GCC makes fatal under
# their -Werror; demote -Werror=discarded-qualifiers. Each plugin warns once
# nixpkgs moves it off the version below: check, then drop it or bump.
{...}: {
  nixpkgs.overlays = [
    (_final: prev: let
      fixWerror = name: brokenVersion: let
        pkg = prev.obs-studio-plugins.${name};
      in
        prev.lib.warnIf (pkg.version != brokenVersion) ''
          modules/pkgs/obs-finitesingularity-werror.nix: nixpkgs' ${name} is now ${pkg.version}.
          Check whether it builds without -Wno-error=discarded-qualifiers; drop it from the override or bump its guard.
        ''
        (pkg.overrideAttrs (old: {
          NIX_CFLAGS_COMPILE =
            (old.NIX_CFLAGS_COMPILE or "")
            + " -Wno-error=discarded-qualifiers";
        }));
    in {
      obs-studio-plugins =
        prev.obs-studio-plugins
        // {
          obs-advanced-masks = fixWerror "obs-advanced-masks" "1.1.0";
          obs-composite-blur = fixWerror "obs-composite-blur" "1.5.2";
          obs-stroke-glow-shadow = fixWerror "obs-stroke-glow-shadow" "v1.5.2";
        };
    })
  ];
}
