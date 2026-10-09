# obs-move-transition: OBS 32.2 deprecated APIs the plugin still uses under
# -Werror=deprecated-declarations; demote the error. Delete once nixpkgs'
# version compiles clean — check when touching this.
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
