# breakpad: Makefile.in's micro/minidump_stackwalk LDADD lists omit
# fast_source_line_resolver.o, so linking fails on its vtable with nixpkgs
# 2026-10-01 (upstream bug, deterministic; --disable-tools doesn't gate it).
# Patches Makefile.in, not .am — no autoreconf step. Drop once nixpkgs or
# upstream fixes it.
{...}: {
  nixpkgs.overlays = [
    (_final: prev: {
      breakpad = prev.breakpad.overrideAttrs (old: {
        postPatch =
          (old.postPatch or "")
          + ''
            for target in microdump_stackwalk minidump_stackwalk; do
              sed -i "/^src_processor_''${target}_LDADD = /,+2{s|^\(\tsrc/processor/basic_source_line_resolver\.o \\\\\)\$|\1\n\tsrc/processor/fast_source_line_resolver.o \\\\|}" Makefile.in
            done
          '';
      });
    })
  ];
}
