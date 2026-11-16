#!/data/data/com.termux/files/usr/bin/sh
# install.sh — run inside Termux from the pushed termux-ssh bundle; installs the SSH config and creates the Keystore key tergent serves.
set -eu
src="$(cd "$(dirname "$0")" && pwd)"

# Termux does not support partial upgrades: mosh linked against a newer libc++ than the bootstrap had.
pkg upgrade -y
pkg install -y openssh mosh termux-api tergent
mkdir -p ~/.ssh
chmod 700 ~/.ssh
install -m 600 "$src/config" ~/.ssh/config
install -m 600 "$src/known_hosts.fleet" ~/.ssh/known_hosts.fleet

if ! termux-keystore list | grep -q '"panther"'; then
  termux-keystore generate panther -a EC -s 256 -u 900
fi
ssh-keygen -D "$PREFIX/lib/libtergent.so"
