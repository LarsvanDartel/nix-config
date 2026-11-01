#!/bin/sh -eu
# judgehost-start — also bind the Nix toolchain (mounted at /chroot/domjudge/nix)
# into each judging's chroot, which only gets a fixed list of directories.
f=/opt/domjudge/judgehost/lib/judge/chroot-startstop.sh
sed -i 's/^SUBDIRMOUNTS="etc usr lib bin"$/SUBDIRMOUNTS="etc usr lib bin nix"/' "$f"
grep -qx 'SUBDIRMOUNTS="etc usr lib bin nix"' "$f"
# Output validators run outside the chroot, where the image has CPython but
# no pypy3; some packages' validator run scripts call pypy3 by name.
ln -sf /usr/bin/python3 /usr/local/bin/pypy3
exec /scripts/start.sh
