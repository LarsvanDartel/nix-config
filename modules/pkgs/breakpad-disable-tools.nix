# breakpad: Makefile.in's micro/minidump_stackwalk LDADD lists omit
# fast_source_line_resolver.o, so linking fails on its vtable with nixpkgs
# 2026-10-01 (upstream bug, deterministic; --disable-tools doesn't gate it).
# Patches Makefile.in, not .am — no autoreconf step. Warns once nixpkgs moves
# breakpad off 2024.02.16: check whether it links, then delete this or bump.
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
