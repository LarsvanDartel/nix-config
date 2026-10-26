# Introduction

lvdar's NixOS fleet config for four hosts (`voyager`, `endeavour`, `gaia`, `pioneer`), built on the **dendritic pattern**: `flake-parts` + `import-tree ./modules`. Every `.nix` file under `modules/` is a flake-parts module, auto-imported. Hosts are assembled from composable **aspects** via [den](https://github.com/denful/den).

## Where to start

- [Hosts](hosts.md) — the four machines, their roles and host facts.
- [Architecture](architecture.md) — evaluation flow, den's composition model, directory layout, cross-host data.
- [Deployment](deployment.md) — build-gate, comin, flake-bump, deploy-rs, the blog bypass.
- [Networking & SSH](networking.md) — the NetBird mesh, publishing services, the SSH trust model.
- [Secrets](secrets.md) — sops-nix, adding a secret, the CI stub.
- [Conventions](conventions.md) — code style, aspect shapes, priority traps, tooling.
- [Commands](commands.md) — everyday commands, testing and QA.
- [Installing a host](install.md) — the installer ISO and `install-host`.
- [Restoring a host](restore.md) — the backup-restore runbook; read its first section before you need it.
