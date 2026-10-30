# Secrets

Secrets are sops-nix, sourced from the private `nix-secrets` flake input over SSH (`git+ssh`). **The flake cannot be evaluated without access to that repo.** Machines without a key (build-gate, flake-bump, CI) build with `--override-input nix-secrets ./.tangled/nix-secrets-stub` (sound because `validateSopsFiles = false`).

## Adding a secret

From the `~/nix-secrets` clone, which has the age key:

```bash
nix run nixpkgs#sops -- set hosts/<host>/secrets.yaml '["keys"]["<service>"]["<name>"]' '"value"'
```

Keys are kebab-case paths nested under `keys`; each host's file is encrypted to that host's age key + the user key (`hosts/common` to all hosts). There is no `delete` subcommand; use `sops unset <file> '<path>'`. Then commit, push, and **update the pin** in nix-config (`nix flake lock --update-input nix-secrets`): hosts read secrets through the flake input, so an un-pushed or un-pinned change is invisible. The consuming aspect must declare the key in `sops.secrets`; a missing key fails `sops-install-secrets` at activation for *every* secret on that host, so land the secret before the config that references it.

## Where keys live

|key|where|decrypted / used by|
|---|---|---|
|host SSH keys (ed25519)|`/persist/etc/ssh/ssh_host_ed25519_key` (`/etc/ssh` on pioneer)|the host itself: its sops age identity (`ssh-to-age`), pinned fleet-wide via the `sshHostKey` fact, and voyager's remote-build identity|
|user age key|`~/.config/sops/age/keys.txt` on voyager, a symlink to `/run/secrets/keys/age`|recipient of every file (`&lvdar` on every creation rule); home-manager's sops decrypts with it|
|`keys/ssh/voyager` (device key), `keys/ssh/idrac`|`hosts/voyager/secrets.yaml`|voyager only, placed by `home.ssh` into `~/.ssh/id_voyager`, `~/.ssh/id_idrac` (and `~/.ssh/id_ed25519` for the device key). Public halves in `modules/den/aspects/core/_ssh-keys/`|
|`keys/flake-bump/ssh-key`|`hosts/endeavour/secrets.yaml`|build-gate and flake-bump on endeavour, pushing to the knot|
|`keys/knot/env` (`KNOT_MASTER_KEY`), `keys/knot/repo-signing-keys`|`hosts/endeavour/secrets.yaml`|knot2: the master key unseals `/tank/knot/sealed-keys` (both are needed to restore the knot); the archive is the old knot's per-repo did:plc rotation keys, re-sealed at every start|
|knot2's SSH host key|`/tank/knot/ssh_host_key` (snapshotted, restic)|presented for `git@knot.lvdar.nl`; its public half is pinned in core.ssh|
|`keys/spindle/key`|`hosts/endeavour/secrets.yaml`|the P-256 key behind the spindle's did:web document|
|`keys/pds/flake-bump-password`|`hosts/endeavour/secrets.yaml`|undeclared; logs in as the flake-bump bot (`flake-bump.pds.lvdar.nl`) to manage its key records|
|YubiKey FIDO2 resident keys|on the YubiKeys (`ssh-keygen -K` recovers the handles)|break-glass root access ([SSH](networking.md#ssh))|

Servers hold no user identity: nothing on endeavour, gaia or pioneer can log in anywhere as lvdar.

## Rotating an SSH key

For a device key (`id_<host>`) or the iDRAC key; flake-bump's works the same with its own file.

1. Generate it outside the repo: `ssh-keygen -t ed25519 -N "" -C lars@lvdar.nl -f /tmp/rot/id_<name>` (the iDRAC key is `-t rsa -b 2048`: its OpenSSH 6.6 cannot parse ed25519 and rejects 4096-bit keys).
2. In `~/nix-secrets`: `nix run nixpkgs#sops -- set hosts/<host>/secrets.yaml '["keys"]["ssh"]["<name>"]' "$(jq -Rs . < /tmp/rot/id_<name>)"`; commit and push.
3. In nix-config: copy the `.pub` to `modules/den/aspects/core/_ssh-keys/id_<name>.pub`, run `nix flake lock --update-input nix-secrets`, and for the device key add the old public key to `allowed_signers` in `home/cli/git.nix` so old commits stay verifiable. Commit, push.
4. Register the new public key where the old one is authorized (GitHub and tangled for the device key, the iDRAC user's SSH keys, the tangled bot key for flake-bump); keep the old one until the switch is done.
5. Roll out so the workstation never loses access: wait for `deploy` and comin on endeavour and gaia (servers now authorize the new key), then `nix run github:serokell/deploy-rs .#pioneer` while voyager still holds the old key, then `nh os switch` on voyager. If anything locks out, use the YubiKey break-glass.
6. Remove the old public key everywhere, then `shred -u /tmp/rot/*`.
