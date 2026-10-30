# wvkbd: binds wl_compositor at version 6 whatever the compositor offers, a
# protocol error that kills it under Umbriel (which offers 5). Bind at most
# what is advertised; v6 only adds the preferred_buffer_scale event. Upstream
# master still binds 6. Warns once nixpkgs moves wvkbd off 0.20: check main.c,
# then delete this or bump.
{...}: {
  nixpkgs.overlays = [
    (_final: prev: {
      wvkbd =
        prev.lib.warnIf (prev.wvkbd.version != "0.20") ''
          modules/pkgs/wvkbd-compositor-version.nix: nixpkgs' wvkbd is now ${prev.wvkbd.version}.
          Check whether main.c still binds wl_compositor at a fixed version 6; delete the override or bump this guard.
        ''
        (prev.wvkbd.overrideAttrs (old: {
          postPatch =
            (old.postPatch or "")
            + ''
              substituteInPlace main.c --replace-fail \
                '&wl_compositor_interface, 6)' \
                '&wl_compositor_interface, version < 6 ? version : 6)'
            '';
        }));
    })
  ];
}
