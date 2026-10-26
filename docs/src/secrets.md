# Secrets

Secrets are sops-nix, sourced from the private `nix-secrets` flake input over SSH (`git+ssh`). **The flake cannot be evaluated without access to that repo.** Machines without a key (build-gate, flake-bump, CI) build with `--override-input nix-secrets ./.tangled/nix-secrets-stub` (sound because `validateSopsFiles = false`).

## Adding a secret

From the `~/nix-secrets` clone, which has the age key:

```bash
nix run nixpkgs#sops -- set hosts/<host>/secrets.yaml '["keys"]["<service>"]["<name>"]' '"value"'
```

Keys are kebab-case paths nested under `keys`; each host's file is encrypted to that host's age key + the user key (`hosts/common` to all hosts). There is no `delete` subcommand; use `sops unset <file> '<path>'`. Then commit, push, and **update the pin** in nix-config (`nix flake lock --update-input nix-secrets`): hosts read secrets through the flake input, so an un-pushed or un-pinned change is invisible. The consuming aspect must declare the key in `sops.secrets`; a missing key fails `sops-install-secrets` at activation for *every* secret on that host, so land the secret before the config that references it.
