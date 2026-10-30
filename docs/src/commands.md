# Commands

```bash
nix fmt                      # treefmt: alejandra + deadnix + shfmt
nix flake check              # everything, incl. deploy-activate (slow: embeds every host's closure)
nix run .#write-flake        # REGENERATE flake.nix after changing any flake-file.inputs
nix build .#docs             # this book; `mdbook serve docs` in the devshell for a live preview

nix build .#nixosConfigurations.<host>.config.system.build.toplevel   # build without switching
nh os switch                 # local voyager switch (also: nh os boot / nh os test)
nix run github:serokell/deploy-rs .#<host>   # manual/out-of-band deploy (magic rollback)
nix run .#update-blocklists  # refresh vendored unbound blocklists, then commit
nix run .#tmux              # wrapped programs carry their own config: also .#yazi .#oh-my-posh .#zathura .#foot

sudo nix run nixpkgs#nixos-facter -- -o modules/den/hosts/_facter/<host>.facter.json   # on the host

nix build .#installer-iso    # cosmos installer ISO (see Installing a host)
nix run .#install-host -- keygen <host> <dir>                                 # new host key + age recipient
nix run .#install-host -- install <host> <ip> --host-key <key> [--copy-persist …]   # nixos-anywhere install
```

## Testing & QA

- No test framework, no coverage expectations. Verification = the change evaluates and builds (`nix build .#nixosConfigurations.<host>...`) and, for the fleet, build-gate turning it green before comin touches a host.
- `nix flake check` covers treefmt, pre-commit hooks, deploy-rs checks (`deploy-activate` is slow), `check-flake-file`, the docs build and the default-shell build.
- CI on the spindle is deliberately fast-feedback: the cheap checks (`treefmt`, `pre-commit`, `check-flake-file`, `default-shell`, `docs`) with `--accept-flake-config` (abort-on-warn applies) and the secrets stub.
- Practical smoke checks when debugging publishing/ingress: `curl -I` against the public name (probes DNS → edge TLS → netbird-proxy → app); `git log deploy..main` shows what has not passed the gate yet.

## Proving a refactor is a no-op

`system.configurationRevision` is stamped from the git rev (`core/revision.nix`), so every commit changes every toplevel drvPath. To prove a refactor is a no-op, compare with it pinned:

```bash
nix eval --raw <ref>#nixosConfigurations.<h> --apply 'c: (c.extendModules {modules = [({lib, ...}: {system.configurationRevision = lib.mkForce "pinned";})];}).config.system.build.toplevel.drvPath'
```
