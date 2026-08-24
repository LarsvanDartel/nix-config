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

# Remote deploy by hand (magic rollback, builds locally and pushes the closure).
# endeavour and gaia normally deploy themselves — see "Deployment" below.
nix run github:serokell/deploy-rs .#<host>

# Wrapped standalone programs (see modules/meta/hm-wrappers.nix)
nix run .#bat
```

There are no tests beyond `nix flake check`; correctness is eval + build.

### Gotchas that will bite

- **`flake.nix` is generated — never edit it.** Inputs are declared as `flake-file.inputs.*` inside the module that actually uses them (feature-local), then `nix run .#write-flake`. The `check-flake-file` check enforces sync.
- **`abort-on-warn = true`.** Any nixpkgs/HM eval warning (deprecation, etc.) is a hard build failure, not a warning. Upgrades that introduce a deprecation warning break the build.
- **`git add` before building.** The flake is a `git+file://` source, so unstaged new files are invisible to `nix build`/`nix flake check` and produce confusing "option does not exist" errors.
- **Files and directories prefixed with `_` are skipped by import-tree.** That's how `_hw/`, `_facter/`, `_niri/`, `_greetd/`, `_styling/`, `_hyprland/`, `_noctalia/`, `_nvim/`, `_minecraft/`, `_unbound/`, `_ssh-keys/` hold plain modules that are `import`ed explicitly (e.g. from a specialisation body) instead of being auto-loaded as flake-parts modules.

## Layout

- `modules/meta/` — flake-level infrastructure: nixpkgs instance + overlay aggregation, treefmt, pre-commit, devshell, deploy-rs nodes, flake-file, `cosmosLib` helpers, hm-wrapper program catalog.
- `modules/pkgs/` — local packages. Each file self-registers into the `nixpkgs.overlays` aggregator option; `modules/den/overlays.nix` composes them into `flake.overlays.default`, which hosts consume via `inputs.self.overlays.default`.
- `modules/den/aspects/` — the actual configuration, ~200 files, grouped `core/ desktop/ hardware/ home/ roles/ services/`.
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
| `voyager` | x86_64 | ThinkPad P1 gen3 laptop, nvidia, Hyprland + Zen browser. Compositor choice is a **boot-time** switch: the base config and a labelled `hyprland` specialisation are identical, and a `niri`/noctalia specialisation is a separate GRUB entry |
| `endeavour` | x86_64 | the workhorse. jellyfin, immich, kanidm, traccar, opencloud/collabora, suwayomi + flaresolverr, ollama + open-webui on a Tesla P100, tangled (knot + spindle), a PDS, minecraft, attic, the VPN-confined `*arr` stack, and the prometheus/grafana/loki/alloy monitoring. ZFS `tank` with sanoid/zed; restic offsite |
| `gaia` | x86_64 | public VPS and the fleet's only ingress. Runs the self-hosted **NetBird control plane**, and `netbird-proxy` terminates TLS and forwards to endeavour over the mesh. Also crowdsec, ntfy, unbound, and the gatus status page. (Pangolin used to be the ingress and is **decommissioned** — do not reintroduce it) |
| `pioneer` | aarch64 | Raspberry Pi 3; built locally under voyager's binfmt emulation, never on the Pi |

Hardware comes from committed **nixos-facter** reports (`hosts/_facter/<host>.facter.json`, regenerate with `sudo nixos-facter -o …` on the host) plus **disko** layouts in `hosts/_hw/<host>/`. Most hosts use impermanence; persisted paths are declared via `cosmos.system.impermanence.persist.directories`.

Secrets are sops-nix, sourced from the private `nix-secrets` flake input over SSH — you cannot evaluate a host without access to that repo.

**Restoring a host: [`docs/RESTORE.md`](docs/RESTORE.md).** Read the first section
before you need it — the restic password and storage-box SSH key are themselves
sops secrets, so they have to exist outside the fleet or the backups cannot be
opened.

## Deployment

**endeavour and gaia deploy themselves. Pushing to `main` is not what deploys them.**

```
push to main  ->  build-gate builds all three x86_64 hosts at that revision
              ->  all green?  fast-forward the `deploy` branch
              ->  comin (on endeavour + gaia) polls the knot, sees `deploy` move,
                  builds and switches itself within ~5 min
```

- `services.build-gate` is the gate. comin has **no magic rollback**, so nothing
  reaches the fleet until it has actually been built. If `deploy` is behind
  `main`, a build is failing — that is the gate doing its job, not a stuck deploy.
- `services.comin` pulls from the knot over public HTTPS. The arrow points
  *inward*: no credential anywhere grants root on the fleet. Pushing to the
  `testing` branch gets `nixos-rebuild test` (activated, not switched) instead.
- **The knot runs on endeavour** (`services.tangled`), published through gaia. So
  endeavour hosts the git remote it deploys itself from. If the knot is down,
  nothing deploys anywhere — which is the intended failure, but it means a change
  that breaks tangled or gaia's proxy can cut off the path used to fix it.
- `services.flake-bump` is a timer on endeavour that refreshes the lock, and
  commits and pushes when green. **The knot therefore gains commits on its own**
  — always pull before pushing, or the push is rejected.
- deploy-rs remains for manual/out-of-band deploys and for hosts that do not run
  comin (voyager, pioneer). voyager is switched locally with `nh os switch`.

Git remotes: `origin` is the knot (`knot.lvdar.nl`, the source of truth that comin
watches) and also lists GitHub as a second **push** URL. Only the knot is a fetch
URL, so a partial push can leave the two out of sync.

## Networking and publishing

- Hosts meet on a **NetBird mesh** (`<host>.nb.lvdar.nl`). The control plane is
  self-hosted on gaia.
- `cosmos.services.netbird.services` on `gaia.nix` is where a service becomes
  public. Entries are either gated behind a NetBird identity check or `shared`
  (open, because the app runs its own login). Gated: `suwayomi`, `sabnzbd`,
  `prowlarr`, `radarr`, `sonarr`, `lidarr`, `bazarr`, `minecraft-control`.
  Everything else — jellyfin, immich, cloud/docs/wopi, chat, grafana, traccar,
  status, ntfy, pds, knot, spindle — is open by design; the reasoning for each is
  in the comments there and is worth reading before changing one.
- `cosmos.networking.edgeTerminated` is per-host and means "TLS for my published
  services is terminated somewhere else". **endeavour is `true`** — gaia
  terminates and forwards over the mesh to each app's own port, so an app there
  must bind the mesh address (`0.0.0.0`) rather than loopback, or the proxy's
  connection is refused, and its local nginx vhost is dropped. **gaia is `false`**
  because gaia *is* the edge. This is the single most common cause of a newly
  published service answering locally but not publicly.

## Conventions

- Commits: conventional-commit style, lowercase, imperative, explaining the *why* (`fix(netbird): move the OIDC callbacks off hash routes`).
- Every file starts with a comment explaining its purpose; non-obvious decisions get a comment explaining the reasoning and the constraint that forced them. Match this — the existing comments are load-bearing documentation.
