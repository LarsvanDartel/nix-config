# breakpad — links the stackwalk tools with the fast_source_line_resolver.o upstream's Makefile.in omits (patched there, not .am: no autoreconf).
{...}: {
  nixpkgs.overlays = [
    (_final: prev: {
      breakpad =
        prev.lib.warnIf (prev.breakpad.version != "2024.02.16") ''
          modules/pkgs/breakpad-disable-tools.nix: nixpkgs' breakpad is now ${prev.breakpad.version}.
          Check whether minidump_stackwalk links without the LDADD patch; delete the override or bump this guard.
        ''
        (prev.breakpad.overrideAttrs (old: {
          postPatch =
            (old.postPatch or "")
            + ''
              for target in microdump_stackwalk minidump_stackwalk; do
                sed -i "/^src_processor_''${target}_LDADD = /,+2{s|^\(\tsrc/processor/basic_source_line_resolver\.o \\\\\)\$|\1\n\tsrc/processor/fast_source_line_resolver.o \\\\|}" Makefile.in
              done
            '';
        }));
    })
  ];
}
