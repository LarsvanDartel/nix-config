# obs-move-transition, unbroken against OBS 32.2.
#
# OBS 32.2 marked obs_properties_add_button (and friends) OBS_DEPRECATED, and
# obs-move-transition 3.2.1 compiles with -Werror=deprecated-declarations. The
# result is a plugin that cannot be built against the OBS it is meant to load
# into: five translation units fail with "all warnings being treated as errors"
# and voyager's home-manager generation dies with them.
#
# This blocks more than OBS. flake-bump builds every host before it will push a
# lock, so one uncompilable leaf on voyager holds the *whole fleet* at an old
# nixpkgs — endeavour and gaia included. That is the gate working as designed,
# which is exactly why the leaf has to be fixed rather than waited out.
#
# Demoting the error is the right scope. These are deprecations, not removals:
# the functions still exist and still work in 32.2, upstream simply intends to
# drop them later. Patching the call sites would mean carrying a fork of a
# plugin whose author will do it properly on his own schedule.
#
# Delete this once nixpkgs ships a version that compiles clean. The build
# failing with "unknown warning option" is not how that will announce itself —
# it will just be dead weight, so check the plugin's version when touching it.
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
