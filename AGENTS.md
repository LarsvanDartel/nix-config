# Repository Guidelines

NixOS fleet config for four hosts (`voyager`, `endeavour`, `gaia`, `pioneer`), built on the **dendritic pattern**: `flake-parts` + `import-tree ./modules`. Every `.nix` file under `modules/` is a flake-parts module, auto-imported. Hosts are assembled from composable **aspects** via [den](https://github.com/denful/den). `CLAUDE.md` is the authoritative long-form doc; this file is the condensed operating manual.

## Architecture & Data Flow

**Evaluation flow**: generated `flake.nix` → `mkFlake` + `import-tree ./modules` → every module auto-loads → den assembles `nixosConfigurations` from aspects → `modules/meta/nixpkgs.nix` injects one shared per-system `pkgs` (stable + unstable + NUR overlays) via `_module.args.pkgs`.

**Composition model** (`modules/den/`):

- **Aspect** = the unit of configuration: `den.aspects.<group>.<name>` with any of `includes` (other aspects), `nixos` (NixOS module), `homeManager` (HM module), `provides.to-users.*`.
- **Roles** (`modules/den/aspects/roles/`) are the only aggregates hosts include: `default` (every host, via `modules/den/defaults.nix`), `server`, `desktop`, `desktop-home`, `gaming`, `home-base` (every user).
- **Hosts** (`modules/den/hosts/<host>.nix`) register `den.hosts.<arch>.<host>.users.<user>` and define a per-host aspect stacking roles + individual aspects + hardware imports.
- Custom options live under **`cosmos.*`**, declared by whichever aspect owns the feature. Frequently used: `cosmos.system.impermanence.persist.*`, `cosmos.networking.edgeTerminated`, `cosmos.services.*`, `cosmos.user.*`.
- **Local packages**: each `modules/pkgs/*.nix` self-registers into the `nixpkgs.overlays` aggregator option; `modules/den/overlays.nix` composes `flake.overlays.default`, consumed by hosts via `inputs.self.overlays.default`.

**Deployment flow** (push to `main` is *not* what deploys):

```
push to main → knot (services.tangled on endeavour)
            → services.build-gate builds gaia+endeavour+voyager (pioneer excluded, aarch64)
            → green? fast-forward `deploy` branch
            → comin (endeavour + gaia) polls the knot over public HTTPS, self-deploys (~5 min)
```

`testing` branch → `nixos-rebuild test` (activated, gone on reboot). flake-bump pushes to `main` autonomously daily — **always pull before pushing**. deploy-rs stays for manual/out-of-band deploys and hosts without comin (voyager: `nh os switch`; pioneer).

**Publishing model**: `cosmos.services.netbird.services` in `gaia.nix` is where a service becomes public (gated behind NetBird identity vs `shared` = open; per-entry comments explain why). `localVhosts` is the escape hatch for domains netbird-proxy cannot carry (the apex `lvdar.nl` 422s). `cosmos.networking.edgeTerminated`: endeavour = `true` (apps must bind `0.0.0.0`, local nginx vhosts dropped), gaia = `false` (is the edge). A new service answering locally but not publicly is almost always a missing bind/`edgeTerminated` issue. netbird-proxy **fails closed** when crowdsec's LAPI is unreachable — check `curl -I` against a published service before blaming the knot.

## Key Directories

| Path | Purpose |
|---|---|
| `modules/meta/` | Flake-level infra: nixpkgs instance + overlay aggregation, treefmt, pre-commit, devshell, deploy-rs nodes, flake-file, `cosmosLib` helpers, hm-wrapper catalog |
| `modules/pkgs/` | Local packages (14 files), each self-registering into the overlays aggregator |
| `modules/den/aspects/` | The configuration itself (~200 files): `core/ desktop/ hardware/ home/ roles/ services/` |
| `modules/den/hosts/` | One aspect-bearing file per host + `_hw/` (disko) + `_facter/` (hardware reports) |
| `modules/den/users/` | User aspects: `lvdar.nix`, `nixos.nix` (batteries + `roles.home-base`) |
| `modules/den/{defaults,deployment}.nix` | Every-host/user baseline; per-deployment facts (only options valid on *every* host) |
| `docs/RESTORE.md` | Host-restore runbook — read its first section before you need it |
| `.tangled/` | Spindle CI workflow (`lint.yml`) + `nix-secrets-stub` used by build-gate/flake-bump/CI |

**`_`-prefixed dirs are skipped by import-tree** — they hold plain modules/assets imported explicitly by the aspect that needs them (e.g. `aspects/home/editor/_nvim/` → `nvim.nix` does `homeManager.imports = [./_nvim]`). Recurring reason: specialisation bodies are plain NixOS modules that cannot `include` den aspects, so shared content lives in parameterized factories (e.g. `_niri/system.nix`) called from both the aspect and the specialisation.

## Development Commands

```bash
nix fmt                      # treefmt: alejandra + deadnix + shfmt
nix flake check              # treefmt, pre-commit, deploy-rs checks, check-flake-file
nix run .#write-flake        # REGENERATE flake.nix after changing any flake-file.inputs

nix build .#nixosConfigurations.<host>.config.system.build.toplevel   # build without switching
nh os switch                 # local voyager switch (also: nh os boot / nh os test)
nix run github:serokell/deploy-rs .#<host>   # manual/out-of-band deploy (magic rollback)
nix run .#bat                # wrapped standalone programs (19, see modules/meta/hm-wrappers.nix)
nix run .#update-blocklists  # refresh vendored unbound blocklists, then commit

sudo nix run nixpkgs#nixos-facter -- -o modules/den/hosts/_facter/<host>.facter.json   # on the host
```

There are no tests beyond `nix flake check`; correctness is eval + build.

## Code Conventions & Common Patterns

- **Every file opens with a `# <name> — <what it is>` purpose comment**; non-obvious decisions get a comment explaining the *why* and the constraint that forced it. The existing comments are load-bearing documentation — match this.
- **Feature-local inputs**: declare `flake-file.inputs.<name>.url` in the module that uses it, then `nix run .#write-flake`. Never edit `flake.nix` (generated; `check-flake-file` enforces sync).
- **Aspect shapes** (simple → full → composite):
  ```nix
  # simple
  den.aspects.services.containers.nixos = {...}: { ... };
  # full: own options under cosmos.*, secrets, impermanence contributions
  den.aspects.services.jellyfin.nixos = {config, lib, ...}: let cfg = config.cosmos.services.jellyfin; in {
    options.cosmos.services.jellyfin.port = mkOption {type = port; default = 8096;};
    config = { sops.secrets...; cosmos.system.impermanence.persist.directories = [{directory = "/var/lib/jellyfin"; user = "jellyfin";}]; };
  };
  # composite
  den.aspects.<x> = { includes = with den.aspects; [roles.server services.netbird.client]; ... };
  ```
- **Recurring option shapes**: `port = mkOption {type = port; default = <n>;}`, `expose = mkOption {type = bool; default = false;}`, `mkEnableOption "..." // {default = true;}` for opt-out enables.
- **Impermanence**: aspects contribute paths declaratively via `cosmos.system.impermanence.persist.directories` (bare path string or `{directory, user, group}` attrset); activation is opt-in via the `core.impermanence` aspect (voyager/endeavour/gaia, not pioneer).
- **Priority discipline**: `mkDefault` for overridable defaults; `mkForce` only for real overrides — and **never at the top level of an aspect body combined with facter** (den unwraps priority wrappers to classify content → infinite recursion). Wrap such modules in an inner `imports = [({...}: {...})]`; see the comment in `modules/den/hosts/pioneer.nix`. Same trap family: avoid config reads in host aspect top level (see `gaia.nix`'s `facter.detected.graphics.enable` comment).
- **homeManager modules** are plain HM modules that freely read `osConfig`; `lib.hm.dag` for ordering.
- **Cross-host values are hand-synced literals** — den cannot read another host's config (e.g. gaia's `netbird.services` hardcodes endeavour's ports; the BMC address in pioneer). When you change a port on one host, grep the others.
- Names: kebab-case aspect names matching their file; nested subdirs extend the namespace (`services/arr/*.nix` → `den.aspects.services.arr.radarr`).

## Important Files

- `flake.nix` — **generated, never edit**; header says so. `nixConfig.abort-on-warn = true`.
- `modules/den/defaults.nix` — what every host/user gets by default.
- `modules/den/deployment.nix` — fleet-wide option values; only options that exist on *every* host belong here, anything narrower goes in the host's own file.
- `modules/den/hosts/gaia.nix` — the publish-or-gate registry (`cosmos.services.netbird.services`); read the per-entry reasoning before changing one.
- `modules/den/hosts/voyager.nix` — boot-time compositor specialisations (base/hyprland + niri as separate GRUB entries).
- `modules/den/aspects/core/{sops,impermanence,impermanence-options,networking}.nix` — secrets, persistence, `edgeTerminated`.
- `modules/meta/{nixpkgs,formatter,pre-commit,devshell,deploy,hm-wrappers}.nix` — flake machinery.
- `modules/den/hosts/_hw/<host>/disko.nix`, `_facter/<host>.facter.json` — declarative hardware; voyager's disko takes `{device}` as an argument.
- `.tangled/workflows/lint.yml` — the only CI (spindle): builds `checks.{treefmt,pre-commit,check-flake-file,default-shell}` with the nix-secrets stub override; does *not* run `nix flake check` wholesale.

## Runtime/Tooling Preferences

- Nix flake workflow only; no justfile, no scripts dir, no GitHub Actions. `.envrc` at root is `use flake`.
- `nixConfig.abort-on-warn = true`: **any nixpkgs/HM eval warning (deprecation etc.) is a hard build failure**, not a warning. Upgrades introducing deprecation warnings break the build.
- Formatter set is fixed: alejandra (Nix) + deadnix + shfmt via treefmt (`modules/meta/formatter.nix`); `flake.nix`, `*.facter.json`, `*hardware-configuration.nix`, `*.lua` are excluded. `.pre-commit-config.yaml` is gitignored — hooks are flake-managed in `modules/meta/pre-commit.nix`.
- **`git add` new files before building** — the flake is a `git+file://` source, so unstaged files are invisible and produce confusing "option does not exist" errors.
- Secrets: sops-nix sourced from the private `nix-secrets` flake input over SSH (`git+ssh`). **The flake cannot be evaluated without access to that repo.** Machines without a key (build-gate, flake-bump, CI) build with `--override-input nix-secrets ./.tangled/nix-secrets-stub` (sound because `validateSopsFiles = false`).
- Git remotes: `origin` = the knot (`knot.lvdar.nl`, what comin watches), sole fetch URL, dual push URLs (knot + GitHub) — a partial push can desync the mirror. Pull before pushing; flake-bump commits on its own.

## Testing & QA

- `nix flake check` is the whole quality gate: treefmt, pre-commit hooks, deploy-rs checks, `check-flake-file` (flake.nix/flake-file.inputs sync), default-shell build.
- CI on the spindle (`.tangled/workflows/lint.yml`) is deliberately fast-feedback: the four cheap checks with `--accept-flake-config` (abort-on-warn applies) and the secrets stub; it excludes deploy checks (they embed every host's closure).
- No test framework, no coverage expectations. Verification = the change evaluates (`nix build .#nixosConfigurations.<host>...` or `nix flake check`) and, for the fleet, build-gate turning it green before comin touches a host.
- Practical smoke checks when debugging publishing/ingress: `curl -I` against the public name (probes DNS → edge TLS → netbird-proxy → app); `git log deploy..main` shows what has not passed the gate yet.
