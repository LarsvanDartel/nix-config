#!/bin/sh -eu
# judgehost-start — binds the Nix toolchain into each judging chroot, which only gets a fixed directory list.
f=/opt/domjudge/judgehost/lib/judge/chroot-startstop.sh
sed -i 's/^SUBDIRMOUNTS="etc usr lib bin"$/SUBDIRMOUNTS="etc usr lib bin nix"/' "$f"
grep -qx 'SUBDIRMOUNTS="etc usr lib bin nix"' "$f"
# Output validators run outside the chroot, which has CPython but no pypy3; some call pypy3 by name.
ln -sf /usr/bin/python3 /usr/local/bin/pypy3
exec /scripts/start.sh
