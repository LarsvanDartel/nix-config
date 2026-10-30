# install-host — key generation and nixos-anywhere installs for fleet hosts; see docs/src/install.md.
# shellcheck shell=bash

usage() {
  cat >&2 <<'EOF'
usage:
  install-host keygen <host> <dir>
  install-host install <host> <target> --host-key FILE [--port N] [--copy-persist]
                       [--exclude-from FILE] [--no-fido2] [--no-reboot]
EOF
  exit 2
}

die() {
  echo "install-host: $*" >&2
  exit 1
}

next_steps() {
  cat <<EOF
next steps (docs/src/install.md, "New host"), in ~/nix-secrets:
  1. .sops.yaml: add the recipient as &$1 and put *$1 on the creation rules
     for hosts/$1/ and hosts/common/
  2. create hosts/$1/secrets.yaml: nix run nixpkgs#sops -- hosts/$1/secrets.yaml
  3. nix run nixpkgs#sops -- updatekeys hosts/$1/secrets.yaml hosts/common/secrets.yaml
  4. commit and push nix-secrets, then in nix-config: nix flake lock --update-input nix-secrets
EOF
}

keygen() {
  [ $# -eq 2 ] || usage
  local host=$1 dir=$2
  local key="$dir/ssh_host_ed25519_key"
  [ -e "$key" ] && die "$key exists; refusing to overwrite a host key"
  mkdir -p "$dir"
  chmod 700 "$dir"
  ssh-keygen -q -t ed25519 -N "" -C "$host.local" -f "$key"
  local recipient
  recipient=$(ssh-to-age <"$key.pub")
  echo "age recipient (add to ~/nix-secrets/.sops.yaml): $recipient"
  echo "sshHostKey for den.hosts.<sys>.$host: $(cut -d' ' -f1,2 "$key.pub")"
  echo
  next_steps "$host"
}

install_host() {
  [ $# -ge 2 ] || usage
  local host=$1 target=$2
  shift 2
  local hostKey="" port=22 copyPersist=0 excludeFrom="" fido2=1 reboot=1
  while [ $# -gt 0 ]; do
    case $1 in
    --host-key)
      [ $# -ge 2 ] || usage
      hostKey=$2
      shift 2
      ;;
    --port)
      [ $# -ge 2 ] || usage
      port=$2
      shift 2
      ;;
    --exclude-from)
      [ $# -ge 2 ] || usage
      excludeFrom=$2
      shift 2
      ;;
    --copy-persist)
      copyPersist=1
      shift
      ;;
    --no-fido2)
      fido2=0
      shift
      ;;
    --no-reboot)
      reboot=0
      shift
      ;;
    *) usage ;;
    esac
  done
  [ -n "$hostKey" ] || usage
  [ -r "$hostKey" ] || die "cannot read host key $hostKey"
  hostKey=$(realpath "$hostKey")
  if [ -n "$excludeFrom" ]; then
    [ "$copyPersist" = 1 ] || die "--exclude-from only applies with --copy-persist"
    [ -r "$excludeFrom" ] || die "cannot read $excludeFrom"
    excludeFrom=$(realpath "$excludeFrom")
  fi

  # 1. Checkout and target.
  local root
  root=$(git rev-parse --show-toplevel 2>/dev/null) || die "run inside the nix-config checkout"
  # The installer's host keys are random per boot.
  local sshOpts=(-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o LogLevel=ERROR)
  local sshT=(ssh -p "$port" "${sshOpts[@]}" "root@$target")
  "${sshT[@]}" test -e /etc/cosmos-installer ||
    die "root@$target:$port is not the cosmos installer (or ssh failed); boot the target from \`nix build .#installer-iso\`"

  # 2. A new host needs a facter report before it evaluates.
  local facter="$root/modules/den/hosts/_facter/$host.facter.json"
  if [ ! -e "$facter" ]; then
    "${sshT[@]}" nixos-facter >"$facter" || {
      rm -f "$facter"
      die "nixos-facter failed on the target"
    }
    git -C "$root" add --intent-to-add --force -- "$facter"
  fi

  # 3. Evaluate.
  cfg() {
    nix eval --json "$root#nixosConfigurations.$host.config.$1" ${2:+--apply "$2"}
  }
  local name keyPath impermanent luks swaps resumeDevice
  name=$(cfg networking.hostName) || die "evaluating $host failed (see above)"
  [ "$(jq -r . <<<"$name")" = "$host" ] || die "nixosConfigurations.$host has hostName $name"
  keyPath=$(cfg sops.age.sshKeyPaths 'builtins.head') || die "evaluating $host failed"
  keyPath=$(jq -r . <<<"$keyPath")
  impermanent=$(cfg cosmos.system.impermanence.active) || die "evaluating $host failed"
  luks=$(cfg boot.initrd.luks.devices 'builtins.mapAttrs (_: d: {inherit (d) device crypttabExtraOpts;})') ||
    die "evaluating $host failed"
  swaps=$(cfg swapDevices 'map (s: s.device)') || die "evaluating $host failed"
  resumeDevice=$(cfg boot.resumeDevice) || die "evaluating $host failed"
  resumeDevice=$(jq -r . <<<"$resumeDevice")

  # 4. The installed host must be able to decrypt its secrets on first boot.
  local secrets age recipient f
  secrets=$(nix flake archive --json "$root" | jq -r '.inputs."nix-secrets".path // empty')
  [ -n "$secrets" ] || secrets=$(nix eval --raw --impure --expr "(builtins.getFlake \"git+file://$root\").inputs.nix-secrets.outPath")
  age=$(ssh-to-age -private-key -i "$hostKey") || die "ssh-to-age failed on $hostKey"
  recipient=$(ssh-keygen -y -f "$hostKey" | ssh-to-age)
  for f in "$secrets/hosts/$host/secrets.yaml" "$secrets/hosts/common/secrets.yaml"; do
    # Clean env and HOME: sops also tries ~/.config/sops/age/keys.txt and
    # ~/.ssh/id_ed25519, and the user key decrypts everything.
    if ! env -i PATH="$PATH" HOME="$tmp" XDG_CONFIG_HOME="$tmp" SOPS_AGE_KEY="$age" \
      sops -d "$f" >/dev/null 2>&1; then
      {
        echo "install-host: the pinned nix-secrets cannot be decrypted with this host key ($f)"
        echo "age recipient: $recipient"
        next_steps "$host"
      } >&2
      exit 1
    fi
  done

  # 5.
  if [ "$copyPersist" = 1 ] && [ "$(cat /proc/sys/kernel/hostname)" != "$host" ]; then
    die "--copy-persist streams THIS machine's /persist; run it on the machine being replaced"
  fi

  # 6. Disko layouts read the passphrase from /tmp/secret.key.
  local luksArgs=()
  if [ "$(jq length <<<"$luks")" -gt 0 ]; then
    local pw pw2
    read -rsp "LUKS passphrase for $host: " pw
    echo
    read -rsp "again: " pw2
    echo
    [ "$pw" = "$pw2" ] || die "passphrases differ"
    [ -n "$pw" ] || die "empty passphrase"
    (
      umask 077
      printf '%s' "$pw" >"$tmp/luks.key"
    )
    luksArgs=(--disk-encryption-keys /tmp/secret.key "$tmp/luks.key")
  fi

  # 7. Always the target's own hardware.
  "${sshT[@]}" nixos-facter >"$facter.tmp" || die "nixos-facter failed on the target"
  mv "$facter.tmp" "$facter"
  git -C "$root" add --intent-to-add --force -- "$facter"

  # 8. The host key (sops identity) and, on impermanent hosts, a machine-id
  # for the rollback unit to seed /etc from.
  local extra="$tmp/extra"
  install -D -m 0600 "$hostKey" "$extra$keyPath"
  if [ -e "$hostKey.pub" ]; then
    install -D -m 0644 "$hostKey.pub" "$extra$keyPath.pub"
  else
    ssh-keygen -y -f "$hostKey" >"$tmp/host.pub"
    install -D -m 0644 "$tmp/host.pub" "$extra$keyPath.pub"
  fi
  if [ "$impermanent" = true ] && [ "$copyPersist" = 0 ]; then
    systemd-id128 new >"$tmp/machine-id"
    install -D -m 0444 "$tmp/machine-id" "$extra/persist/etc/machine-id"
  fi

  # 9. Built here: only this machine can fetch the private nix-secrets.
  nixos-anywhere --flake "$root#$host" --target-host "root@$target" --ssh-port "$port" \
    --build-on local --phases disko,install \
    --ssh-option StrictHostKeyChecking=no --ssh-option UserKnownHostsFile=/dev/null \
    --extra-files "$extra" "${luksArgs[@]}"

  # 9b. FIDO2, while the passphrase file is still on the installer.
  local fidoDevs=() enrolled=() dev ans
  mapfile -t fidoDevs < <(jq -r 'to_entries[] | select(any(.value.crypttabExtraOpts[]; startswith("fido2-device"))) | .value.device' <<<"$luks")
  if [ "$fido2" = 1 ]; then
    for dev in "${fidoDevs[@]}"; do
      while :; do
        read -rp "Plug a FIDO2 key into the TARGET and press Enter to enroll it into $dev (type \"done\" to stop): " ans
        [ "$ans" = "done" ] && break
        if ssh -t -p "$port" "${sshOpts[@]}" "root@$target" \
          systemd-cryptenroll --fido2-device=auto --unlock-key-file=/tmp/secret.key "$dev"; then
          enrolled+=("$dev")
        else
          echo "enrolment failed; after first boot run: sudo systemd-cryptenroll --fido2-device=auto $dev"
        fi
      done
    done
  fi

  # 10.
  if [ "$copyPersist" = 1 ]; then
    local excludeArgs=() st tarBin
    [ -n "$excludeFrom" ] && excludeArgs=(--exclude-from="$excludeFrom")
    tarBin=$(command -v tar)
    sudo -v
    set +e
    sudo "$tarBin" -C /persist --anchored --wildcards "${excludeArgs[@]}" --xattrs --acls --numeric-owner -cpf - . |
      pv | "${sshT[@]}" "tar -C /mnt/persist --xattrs --acls --numeric-owner -xpf -"
    st=("${PIPESTATUS[@]}")
    set -e
    # tar exits 1 for "file changed as we read it".
    if ! { [ "${st[0]}" -le 1 ] && [ "${st[1]}" = 0 ] && [ "${st[2]}" = 0 ]; }; then
      die "copying /persist failed (tar ${st[0]}, pv ${st[1]}, receiver ${st[2]})"
    fi
  fi

  # 11.
  if [ "$copyPersist" = 1 ] || [ "$reboot" = 0 ]; then
    echo "target left in the installer with /mnt mounted. Power off THIS machine first if the target takes over its identity, then on the target run: swapoff -a; umount -R /mnt; reboot"
  else
    "${sshT[@]}" 'swapoff -a; umount -R /mnt; systemctl reboot' || true
  fi

  # 12.
  echo
  echo "post-install checklist:"
  echo "  - commit modules/den/hosts/_facter/$host.facter.json"
  echo "  - den.hosts.<sys>.$host.sshHostKey = \"$(cut -d' ' -f1,2 "$extra$keyPath.pub")\";"
  for dev in "${fidoDevs[@]}"; do
    if [[ " ${enrolled[*]} " != *" $dev "* ]]; then
      echo "  - on $host: sudo systemd-cryptenroll --fido2-device=auto $dev"
    fi
  done
  if [ -n "$resumeDevice" ]; then
    local swap
    for swap in $(jq -r '.[]' <<<"$swaps"); do
      echo "  - on $host: sudo btrfs inspect-internal map-swapfile -r $swap -> set resume_offset=<n> for $host"
    done
  fi
}

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

[ $# -ge 1 ] || usage
cmd=$1
shift
case $cmd in
keygen) keygen "$@" ;;
install) install_host "$@" ;;
*) usage ;;
esac
