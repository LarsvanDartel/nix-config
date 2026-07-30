# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this is

lvdar's NixOS configuration for four hosts, built on the **dendritic pattern**: `flake-parts` + `import-tree ./modules`. Every `.nix` file under `modules/` is a flake-parts module, auto-imported. Hosts are assembled by [den](https://github.com/denful/den) from composable *aspects*.

## Commands

```bash
nix fmt                      # treefmt: alejandra + deadnix + shfmt
nix flake check              # treefmt, pre-commit, deploy-rs checks, check-flake-file
nix run .#write-flake        # REGENERATE flake.nix after changing any flake-file.inputs

# Build a host without switching
nix build .#nixosConfigurations.<host>.config.system.build.toplevel

# Local switch (voyager)
nh os switch      # or: nh os boot / nh os test

# Remote deploy (magic rollback, builds locally and pushes the closure)
nix run github:serokell/deploy-rs .#<host>

# Wrapped standalone programs (see modules/meta/hm-wrappers.nix)
nix run .#bat
```

There are no tests beyond `nix flake check`; correctness is eval + build.

### Gotchas that will bite

- **`flake.nix` is generated — never edit it.** Inputs are declared as `flake-file.inputs.*` inside the module that actually uses them (feature-local), then `nix run .#write-flake`. The `check-flake-file` check enforces sync.
- **`abort-on-warn = true`.** Any nixpkgs/HM eval warning (deprecation, etc.) is a hard build failure, not a warning. Upgrades that introduce a deprecation warning break the build.
- **`git add` before building.** The flake is a `git+file://` source, so unstaged new files are invisible to `nix build`/`nix flake check` and produce confusing "option does not exist" errors.
- **Files and directories prefixed with `_` are skipped by import-tree.** That's how `_hw/`, `_facter/`, `_niri/`, `_greetd/`, `_styling/` hold plain modules that are `import`ed explicitly (e.g. from a specialisation body) instead of being auto-loaded as flake-parts modules.

## Layout

- `modules/meta/` — flake-level infrastructure: nixpkgs instance + overlay aggregation, treefmt, pre-commit, devshell, deploy-rs nodes, flake-file, `cosmosLib` helpers, hm-wrapper program catalog.
- `modules/pkgs/` — local packages. Each file self-registers into the `nixpkgs.overlays` aggregator option; `modules/den/overlays.nix` composes them into `flake.overlays.default`, which hosts consume via `inputs.self.overlays.default`.
- `modules/den/aspects/` — the actual configuration, ~160 files, grouped `core/ desktop/ hardware/ home/ roles/ services/`.
- `modules/den/hosts/` — one file per host; `modules/den/users/` — one per user.

## den model

An aspect is a named, composable unit declaring any of `includes` (other aspects), `nixos` (a NixOS module), `homeManager` (an HM module), `provides.to-users.*`:

```nix
{den, ...}: {
  den.aspects.services.foo = {
    includes = [den.aspects.services.nginx];
    nixos = {config, lib, ...}: { ... };
  };
}
```

`roles/*` are the aggregates (`roles.server`, `roles.desktop`, `roles.desktop-home`, `roles.home-base`, `roles.gaming`); hosts include roles plus individual aspects. `modules/den/defaults.nix` sets what every host/user gets by default (batteries, `core.nixpkgs`, `core.home-manager`, HM class for all users, `roles.default`).

Custom options live under the **`cosmos.*`** namespace (`cosmos.system.impermanence`, `cosmos.services.netbird`, `cosmos.cli.programs.nvim.languages`, `cosmos.desktops.*`, …), declared in whichever aspect owns them.

### den quirks

- A `mkForce`/`mkDefault` at the top level of an aspect body **infinitely recurses when combined with facter** — den classifies aspect content by unwrapping priority wrappers, forcing the definition too early. Put such a module inside `imports` instead, where it stays opaque to den until the NixOS module system evaluates it. See the comment in `modules/den/hosts/pioneer.nix`.
- den cannot read another host's config. Cross-host references (ports, addresses) are literals that must be kept in sync by hand — e.g. `cosmos.services.netbird.services` in `gaia.nix` hardcodes endeavour's service ports.
- `mkForce` inside an `attrsOf` submodule doesn't do what you want for Hyprland Lua-ish config; suppress bad output with `stylix.targets.<t>.disable` instead.

## Hosts

| host | arch | role |
|---|---|---|
| `voyager` | x86_64 | ThinkPad P1 gen3 laptop, nvidia, Hyprland (+ a `niri`/noctalia **specialisation** as a separate GRUB entry) |
| `endeavour` | x86_64 | media/services server: jellyfin, immich, kanidm, traccar, the VPN-confined `*arr` stack |
| `gaia` | x86_64 | public VPS: the only ingress — Pangolin + the self-hosted NetBird control plane |
| `pioneer` | aarch64 | Raspberry Pi 3; built locally under voyager's binfmt emulation, never on the Pi |

Hardware comes from committed **nixos-facter** reports (`hosts/_facter/<host>.facter.json`, regenerate with `sudo nixos-facter -o …` on the host) plus **disko** layouts in `hosts/_hw/<host>/`. Most hosts use impermanence; persisted paths are declared via `cosmos.system.impermanence.persist.directories`.

Secrets are sops-nix, sourced from the private `nix-secrets` flake input over SSH — you cannot evaluate a host without access to that repo.

## Conventions

- Commits: conventional-commit style, lowercase, imperative, explaining the *why* (`fix(netbird): move the OIDC callbacks off hash routes`).
- Every file starts with a comment explaining its purpose; non-obvious decisions get a comment explaining the reasoning and the constraint that forced them. Match this — the existing comments are load-bearing documentation.
