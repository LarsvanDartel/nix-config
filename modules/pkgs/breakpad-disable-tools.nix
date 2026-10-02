# breakpad fails against nixpkgs 2026-10-01: `undefined reference to vtable
# for google_breakpad::FastSourceLineResolver::Module` linking
# microdump_stackwalk/minidump_stackwalk — binaries noctalia-qs's buildInput
# pulls in as a side effect but never actually links against itself (it only
# needs libbreakpad_client.a).
#
# Root cause, confirmed against breakpad's own upstream source at the pinned
# rev (v2024.02.16): `src_processor_microdump_stackwalk_LDADD` and
# `src_processor_minidump_stackwalk_LDADD` in Makefile.in link
# `source_line_resolver_base.o` (which references
# `google_breakpad::FastSourceLineResolver::Module`, declared in
# `fast_source_line_resolver_types.h`) but never list
# `fast_source_line_resolver.o` — the one translation unit that actually
# defines that class's vtable. A genuine missing-object-file bug in
# breakpad's own Makefile, not a toolchain regression: older/laxer linkers
# just didn't error on it. Confirmed NOT a parallel-build race — reproduces
# identically and deterministically on every rebuild, with or without
# `enableParallelBuilding`. `--disable-tools` (what nixpkgs already passes
# for musl) does not gate these two targets either — rebuilt with it forced
# on unconditionally, identical failure.
#
# Fix: add the missing object to both LDADD lists, in Makefile.in (not
# Makefile.am — this ships a pre-generated `./configure` + Makefile.in, no
# autoreconf step, so configure regenerates the real Makefile from this).
# Scoped to the two `_LDADD = ` lines specifically (not a blanket
# s/basic_source_line_resolver/&\nfast_source_line_resolver/, which would
# also hit the dozen unittest LDADD lists that don't need it). Verified:
# rebuilds clean, produces the same binaries/libs/pkgconfig as an unpatched
# successful build, including the two previously-broken tools.
#
# Drop once nixpkgs' breakpad expression patches this itself, or upstream
# fixes the Makefile.
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
