#!/usr/bin/env bash
# apparmor-collect — prints "<tag>\t<resolved path>" for every executable on this host (installed, running, systemd ExecStart); input for match.py.
# Run as a sudoer: `ssh <host> 'bash -s' < collect.sh > <host>.tsv` (locally: `bash collect.sh > voyager.tsv`).
{
  for d in /run/current-system/sw/bin /run/current-system/sw/sbin /run/current-system/sw/libexec /run/current-system/sw/lib/systemd /etc/profiles/per-user/*/bin /home/*/.local/state/nix/profiles/profile/bin /home/*/.local/state/nix/profiles/profile/libexec /run/wrappers/bin; do
    case "$d" in /home/agent/*) continue ;; esac
    [ -d "$d" ] || continue
    find -L "$d" -maxdepth 3 -type f -perm -u+x 2>/dev/null | while read -r f; do
      printf 'inst\t%s\n' "$(readlink -f "$f")"
    done
  done
  for p in /proc/[0-9]*; do
    e=$(sudo -n readlink "$p/exe" 2>/dev/null || readlink "$p/exe" 2>/dev/null) && printf 'run\t%s\n' "$e"
  done
  systemctl show '*' -p ExecStart --value 2>/dev/null | grep -oE 'path=[^ ;]+' | sed 's/path=//' | while read -r f; do
    printf 'unit\t%s\n' "$(readlink -f "$f")"
  done
} | sort -u
