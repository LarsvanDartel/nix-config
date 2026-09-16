# obs-move-transition, unbroken against OBS 32.2: OBS marked
# obs_properties_add_button and friends deprecated and the plugin builds
# with -Werror=deprecated-declarations. Demoting the error is the right
# scope — the functions still work in 32.2, and patching call sites would
# mean carrying a fork. Delete once nixpkgs ships a version that compiles
# clean; that will not announce itself, so check the plugin's version when
# touching this.
{...}: {
  nixpkgs.overlays = [
    (_final: prev: {
      obs-studio-plugins =
        prev.obs-studio-plugins
        // {
          obs-move-transition =
            prev.obs-studio-plugins.obs-move-transition.overrideAttrs
            (old: {
              env =
                (old.env or {})
                // {
                  NIX_CFLAGS_COMPILE =
                    (old.env.NIX_CFLAGS_COMPILE or "")
                    + " -Wno-error=deprecated-declarations";
                };
            });
        };
    })
  ];
}
