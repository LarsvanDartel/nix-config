#!/data/data/com.termux/files/usr/bin/sh
# install.sh — run inside Termux from the pushed termux-ssh bundle; installs the SSH config and keystore-agent, and starts the agent with each shell.
set -eu
src="$(cd "$(dirname "$0")" && pwd)"

pkg install -y openssh python termux-api
mkdir -p ~/.ssh
chmod 700 ~/.ssh
install -m 600 "$src/config" ~/.ssh/config
install -m 600 "$src/known_hosts.fleet" ~/.ssh/known_hosts.fleet
install -m 700 "$src/keystore-agent" ~/.ssh/keystore-agent

line='(~/.ssh/keystore-agent >/dev/null 2>&1 &)'
touch ~/.bashrc
grep -qxF "$line" ~/.bashrc || printf '%s\n' "$line" >>~/.bashrc
(~/.ssh/keystore-agent >/dev/null 2>&1 &)

if ! termux-keystore list | grep -q '"panther"'; then
  termux-keystore generate panther -a EC -s 256 -u 900
fi
sleep 1
SSH_AUTH_SOCK=~/.ssh/keystore-agent.sock ssh-add -L
