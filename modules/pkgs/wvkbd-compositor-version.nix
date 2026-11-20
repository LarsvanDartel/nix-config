# wvkbd — binds wl_compositor at most at the advertised version, not always 6 (a protocol error under Umbriel, which offers 5).
{...}: {
  nixpkgs.overlays = [
    (_final: prev: {
      wvkbd =
        prev.lib.warnIf (prev.wvkbd.version != "0.21") ''
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
