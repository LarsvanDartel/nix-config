# Repository Guidelines

lvdar's NixOS fleet config for four hosts (`voyager`, `endeavour`, `gaia`, `pioneer`), built on the dendritic pattern (`flake-parts` + `import-tree ./modules`). Hosts are assembled from composable aspects via [den](https://github.com/denful/den).

## Docs

The handbook is the mdBook in `docs/` (`nix build .#docs`). Read the relevant page before changing an area.

|page|topics|
|---|---|
|[`introduction.md`](docs/src/introduction.md)|what the repo is, where to start|
|[`hosts.md`](docs/src/hosts.md)|the four hosts and their roles, host facts, facter/disko/impermanence|
|[`architecture.md`](docs/src/architecture.md)|evaluation flow, den composition model, key directories, `_`-prefixed files, cross-host data (facts, quirks, literals)|
|[`deployment.md`](docs/src/deployment.md)|build-gate, comin, knot, flake-bump, deploy-rs, the blog bypass|
|[`networking.md`](docs/src/networking.md)|NetBird mesh, publishing and gating services, `localVhosts`, `edgeTerminated`, SSH|
|[`secrets.md`](docs/src/secrets.md)|sops-nix, adding a secret, the nix-secrets stub|
|[`conventions.md`](docs/src/conventions.md)|code conventions, aspect and option shapes, priority discipline, wrapped programs, nvim/launchpad, tooling, important files|
|[`commands.md`](docs/src/commands.md)|development commands, testing & QA, the configurationRevision pinning trick|
|[`install.md`](docs/src/install.md)|installing a host|
|[`restore.md`](docs/src/restore.md)|restoring a host from backup|

## Keeping docs in sync

- A change to anything a page describes updates that page in the same commit. This covers hosts and their roles, aspects that publish or gate services, deployment/CI flow, networking/SSH trust, secrets layout, install/restore steps, commands, and conventions.
- Adding or removing a host, flake app/package, or published service updates `hosts.md`, `commands.md`, or `networking.md` respectively.
- A new page needs a `SUMMARY.md` entry; `nix build .#checks.x86_64-linux.docs` must pass. CI runs it.
- This file keeps only agent rules and links. Explanations belong in `docs/`.

## Hard rules

- Never edit `flake.nix`; run `nix run .#write-flake` after changing `flake-file.inputs` ([conventions](docs/src/conventions.md#code)).
- `git add` new files before building ([conventions](docs/src/conventions.md#tooling)).
- `abort-on-warn`: any eval warning fails the build ([conventions](docs/src/conventions.md#tooling)).
- Keyless builds use `--override-input nix-secrets ./.tangled/nix-secrets-stub` ([secrets](docs/src/secrets.md)).
- `# deadnix: skip` on the line above den-dispatched lambda args such as `{host, ...}:` ([conventions](docs/src/conventions.md#tooling)).
- Never `mkForce` at the top level of an aspect body with facter; wrap it in an inner `imports` ([conventions](docs/src/conventions.md#code)).
- Never read config in a host aspect's top level ([conventions](docs/src/conventions.md#code)).
- Never `hasAspect` in an `includes` list ([conventions](docs/src/conventions.md#code)).
- `homeManager` on a host-scope aspect is dropped; use `provides.to-users` ([architecture](docs/src/architecture.md#composition-model)).
- Every file opens with a `# <name> — <what it is>` comment; other comments only to prevent mistakes ([conventions](docs/src/conventions.md#code)).
- Temporary fixes carry a `lib.warnIf` guard on the condition that obsoletes them ([conventions](docs/src/conventions.md#code)).
- Pangolin is decommissioned; do not reintroduce it ([hosts](docs/src/hosts.md)).
- Pull before push: flake-bump commits to `main` on its own ([deployment](docs/src/deployment.md)).
- Verification = `nix build .#nixosConfigurations.<host>.config.system.build.toplevel` ([commands](docs/src/commands.md#testing--qa)).
- `_`-prefixed files are not auto-imported ([architecture](docs/src/architecture.md#_-prefixed-files)).
- Conventional commits, lowercase, explaining why ([conventions](docs/src/conventions.md#code)).
