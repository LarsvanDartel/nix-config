#!/bin/sh -eu
# judgehost-start — also bind the Nix toolchain (mounted at /chroot/domjudge/nix)
# into each judging's chroot, which only gets a fixed list of directories.
f=/opt/domjudge/judgehost/lib/judge/chroot-startstop.sh
sed -i 's/^SUBDIRMOUNTS="etc usr lib bin"$/SUBDIRMOUNTS="etc usr lib bin nix"/' "$f"
grep -qx 'SUBDIRMOUNTS="etc usr lib bin nix"' "$f"
exec /scripts/start.sh
