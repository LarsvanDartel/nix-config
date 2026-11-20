# obs-move-transition — demotes -Werror=deprecated-declarations: the plugin still uses APIs OBS 32.2 deprecated.
{...}: {
  nixpkgs.overlays = [
    (_final: prev: {
      obs-studio-plugins =
        prev.obs-studio-plugins
        // {
          obs-move-transition = let
            pkg = prev.obs-studio-plugins.obs-move-transition;
          in
            prev.lib.warnIf (pkg.version != "3.2.1-unstable-2026-10-04") ''
              modules/pkgs/obs-move-transition.nix: nixpkgs' obs-move-transition is now ${pkg.version}.
              Check whether it builds without -Wno-error=deprecated-declarations; delete the override or bump this guard.
            ''
            (pkg.overrideAttrs (old: {
              env =
                (old.env or {})
                // {
                  NIX_CFLAGS_COMPILE =
                    (old.env.NIX_CFLAGS_COMPILE or "")
                    + " -Wno-error=deprecated-declarations";
                };
            }));
        };
    })
  ];
}
