# Repository Guidelines

lvdar's NixOS fleet config for four hosts (`voyager`, `endeavour`, `gaia`, `pioneer`), built on the **dendritic pattern**: `flake-parts` + `import-tree ./modules`. Every `.nix` file under `modules/` is a flake-parts module, auto-imported. Hosts are assembled from composable **aspects** via [den](https://github.com/denful/den). This file is the single source of truth for working in the repo.

## Hosts

| host | arch | role |
|---|---|---|
| `voyager` | x86_64 | ThinkPad P1 gen3 laptop, nvidia, Hyprland + Zen browser. Compositor choice is a **boot-time** switch: the base config and a labelled `hyprland` specialisation are identical, and a `niri`/noctalia specialisation is a separate GRUB entry |
| `endeavour` | x86_64 | the workhorse. jellyfin, immich, kanidm, traccar, opencloud/collabora, suwayomi + flaresolverr, ollama + librechat (chat.lvdar.nl, local models + OpenRouter) on a Tesla P100, tangled (knot + spindle), a PDS, minecraft (packwiz packs from the `modpacks` input, also served to players at packs.lvdar.nl), attic, `services.site` (lvdar.nl), DOMjudge (judge.lvdar.nl: podman containers with CHipCie practice contests; extra judge languages live in `services/domjudge/languages.nix`), the VPN-confined `*arr` stack, and the prometheus/grafana/loki/alloy monitoring. ZFS `tank` with sanoid/zed; restic offsite |
| `gaia` | x86_64 | public VPS and the fleet's only ingress. Runs the self-hosted **NetBird control plane**, and `netbird-proxy` terminates TLS and forwards to endeavour over the mesh. Also crowdsec, ntfy, stalwart, unbound, the gatus status page, and the vhosts its own nginx serves directly (`localVhosts`). Pangolin used to be the ingress and is **decommissioned** — do not reintroduce it |
| `pioneer` | aarch64 | Raspberry Pi 3; built locally under voyager's binfmt emulation, never on the Pi. Publishes endeavour's **iDRAC** (`services.idrac`) to the mesh — it shares nothing with endeavour but a switch, which is the whole point: out-of-band management proxied by the machine it exists to recover is not out-of-band |

Hardware comes from committed **nixos-facter** reports (`hosts/_facter/<host>.facter.json`) plus **disko** layouts in `hosts/_hw/<host>/`. voyager, endeavour and gaia use impermanence (pioneer does not).

## Architecture & Data Flow

**Evaluation flow**: generated `flake.nix` → `mkFlake` + `import-tree ./modules` → every module auto-loads → den assembles `nixosConfigurations` from aspects → each host builds its own `pkgs` in `core.nixpkgs` (stable + unstable + NUR + `inputs.self.overlays.default`). `modules/meta/nixpkgs.nix` is perSystem's pkgs only (packages, devshell).

**Composition model** (`modules/den/`):

- **Aspect** = the unit of configuration: `den.aspects.<group>.<name>` with any of `includes` (other aspects), `nixos` (NixOS module), `homeManager` (HM module), `provides.*` (cross-entity edges, below), and quirk keys (`kanidm-provision`, `netbird-service`, `scrape-target`, `mesh-dns-record`).
- **Where config lands**: host scope delivers only `nixos`; a `homeManager` key on a host-included aspect is **silently dropped**. Host → its users: `provides.to-users` (e.g. `services.eduvpn`, `roles.gaming`, `desktop.hyprland`, `desktop.styling`, `services.netbird-gewis`). User → its hosts: `provides.to-hosts` (e.g. `home.kde-connect`, `home.catt`, `home.taskwarrior`). Never a plain `nixos` key on a user-scope aspect: that only works through den bug #694. Host-specific user config goes in `den.aspects.<host>.provides.<user>`, not a host child named after the user.
- **Roles** (`modules/den/aspects/roles/`): `default` (every host, `den.schema.host.includes`), `server` (via the `server-role` policy when the host entity has `server = true`), `desktop`, `desktop-home`, `gaming`, `home-base` (every user, `den.schema.user.includes`).
- **Hosts** (`modules/den/hosts/<host>.nix`) register `den.hosts.<arch>.<host> = { users.<user> = {}; meshAddress; server; deployAddress; }` (facts declared in `modules/den/schema.nix`) and define a per-host aspect stacking roles + individual aspects + hardware imports. Every host has exactly one user (asserted); `cosmos.user.name` is derived from it.
- `modules/den/defaults.nix`: what every host/user gets (batteries, `core.nixpkgs`, `core.home-manager`, HM class for all users, `roles.default` per host, user-shell zsh + `roles.home-base` per user).
- Custom options live under **`cosmos.*`**, declared by whichever aspect owns the feature. Frequently used: `cosmos.system.impermanence.persist.*`, `cosmos.networking.edgeTerminated`, `cosmos.services.*`, `cosmos.user.*`.
- **Local packages**: each `modules/pkgs/*.nix` self-registers into the `nixpkgs.overlays` aggregator option; `modules/den/overlays.nix` composes `flake.overlays.default`, consumed by hosts via `inputs.self.overlays.default`.

**Deployment flow** — endeavour and gaia deploy themselves; pushing to `main` is *not* what deploys them:

```
push to main → knot (services.tangled on endeavour)
            → services.build-gate builds gaia+endeavour+voyager (pioneer excluded, aarch64)
            → green? fast-forward `deploy` branch
            → comin (endeavour + gaia) polls the knot over public HTTPS, self-deploys (~5 min)
```

- build-gate is the gate because comin has **no magic rollback**: nothing reaches the fleet until it has been built. `deploy` behind `main` means a build is failing — the gate doing its job, not a stuck deploy (`git log deploy..main`).
- comin pulls, so no credential anywhere grants root on the fleet. `testing` branch → `nixos-rebuild test` (activated, gone on reboot).
- **The knot runs on endeavour** and is published through gaia, so endeavour deploys itself from a remote it hosts. If the knot or gaia's proxy is down, nothing deploys anywhere — and a change that breaks either can cut off the path used to fix it. comin fetches through netbird-proxy like any visitor, and the proxy fails **closed** when crowdsec's LAPI is unreachable: on 2026-08-29 a crowdsec that lost a DNS race 403'd the whole published surface *and* comin for six hours. Check `curl -I` against a published service before blaming the knot.
- `services.flake-bump` (timer on endeavour) refreshes the lock and pushes to `main` when green — **always pull before pushing**.
- deploy-rs stays for manual/out-of-band deploys and hosts without comin (pioneer); voyager switches locally with `nh os switch`.
- **The blog bypasses all of this**: `services.site` polls its own content repository and recompiles when it moves, so publishing a post is a push, not a deploy. Only the site's *code* arrives through the flake input.

**Networking and publishing**:

- Hosts meet on a **NetBird mesh** (`<host>.nb.lvdar.nl`); the control plane is self-hosted on gaia.
- An app aspect becomes public by emitting a `netbird-service = {host, ...}: { <name> = {...}; }` entry (same shape as `cosmos.services.netbird.services.<name>`). gaia's netbird server collects them (`pipe.collect`, x86_64 only) into `cosmos.services.netbird.services`; the producer also appends its port to `cosmos.services.netbird.client.exposedPorts`. Entries are gated behind a NetBird identity check unless `bearerAuth.enable = false` (open because the app runs its own login). Gated: `suwayomi`, `sabnzbd`, `prowlarr`, `radarr`, `sonarr`, `lidarr`, `bazarr`, `lingarr`, `minecraft-control`. The reasoning for each entry sits next to it in the app's aspect — read it before changing gating.
- `cosmos.services.netbird.localVhosts` (gaia) is the escape hatch for domains netbird-proxy *cannot* carry: management rejects any domain that is not a label beneath the proxy's `baseDomain`, so the apex `lvdar.nl` 422s and is served by gaia's own nginx over the mesh instead. Side effect when debugging: the apex keeps working when the proxy does not.
- `cosmos.networking.edgeTerminated`: endeavour = `true` (gaia terminates TLS and forwards to each app's own port, so apps must bind `0.0.0.0` and local nginx vhosts are dropped), gaia = `false` (it *is* the edge). A new service answering locally but not publicly is almost always a missing bind/`edgeTerminated` issue.

## Key Directories

| Path | Purpose |
|---|---|
| `modules/meta/` | Flake-level infra: perSystem nixpkgs, treefmt, pre-commit, devshell, deploy-rs nodes (from `den.hosts`), flake-file, `cosmosLib` helpers |
| `modules/pkgs/` | Local packages, each self-registering into the overlays aggregator |
| `modules/den/aspects/` | The configuration itself (~200 files): `core/ desktop/ hardware/ home/ roles/ services/` |
| `modules/den/hosts/` | One aspect-bearing file per host + `_hw/` (disko) + `_facter/` (hardware reports) |
| `modules/den/users/` | User aspects: `lvdar.nix` (the `nixos` server user needs none) |
| `modules/den/schema.nix` | Host entity facts (`meshAddress`, `server`, `deployAddress`) + the `server-role` policy |
| `modules/den/defaults.nix` | Every-host/user baseline |
| `modules/den/deployment.nix` | Facts about *this* deployment, applied to every host via `den.default.nixos` — values that would otherwise hide as option defaults inside aspects. Only options that exist on *every* host; anything narrower goes in that host's file |
| `docs/RESTORE.md` | Host-restore runbook — read its first section before you need it: the restic password and storage-box SSH key are themselves sops secrets, so they must exist outside the fleet |
| `.tangled/` | Spindle CI workflow (`lint.yml`) + `nix-secrets-stub` used by build-gate/flake-bump/CI |

**`_`-prefixed files/dirs are skipped by import-tree** — they hold plain modules/assets imported explicitly by the aspect that needs them (e.g. `aspects/home/desktop/_styling/` → `styling.nix` does `homeManager.imports = [./_styling]`). Recurring reason: specialisation bodies are plain NixOS modules that cannot `include` den aspects, so shared content lives in parameterized factories (e.g. `_niri/system.nix`) called from both the aspect and the specialisation.

## Development Commands

```bash
nix fmt                      # treefmt: alejandra + deadnix + shfmt
nix flake check              # everything, incl. deploy-activate (slow: embeds every host's closure)
nix run .#write-flake        # REGENERATE flake.nix after changing any flake-file.inputs

nix build .#nixosConfigurations.<host>.config.system.build.toplevel   # build without switching
nh os switch                 # local voyager switch (also: nh os boot / nh os test)
nix run github:serokell/deploy-rs .#<host>   # manual/out-of-band deploy (magic rollback)
nix run .#update-blocklists  # refresh vendored unbound blocklists, then commit
nix run .#tmux              # wrapped programs carry their own config: also .#yazi .#oh-my-posh .#zathura .#foot

sudo nix run nixpkgs#nixos-facter -- -o modules/den/hosts/_facter/<host>.facter.json   # on the host
```

**Adding a secret** (from the `~/nix-secrets` clone, which has the age key): `nix run nixpkgs#sops -- set hosts/<host>/secrets.yaml '["keys"]["<service>"]["<name>"]' '"value"'`. Keys are kebab-case paths nested under `keys`; each host's file is encrypted to that host's age key + the user key (`hosts/common` to all hosts). There is no `delete` subcommand; use `sops unset <file> '<path>'`. Then commit, push, and **update the pin** here (`nix flake lock --update-input nix-secrets`): hosts read secrets through the flake input, so an un-pushed or un-pinned change is invisible. The consuming aspect must declare the key in `sops.secrets`; a missing key fails `sops-install-secrets` at activation for *every* secret on that host, so land the secret before the config that references it.

## Code Conventions & Common Patterns

- **Commits**: conventional-commit style, lowercase, imperative, explaining the *why* (`fix(netbird): move the OIDC callbacks off hash routes`).
- **Every file opens with a `# <name> — <what it is>` purpose comment**. Beyond that, comments earn their place by preventing a future mistake: a trap, a security decision, a hand-synced cross-host value, a packaging pin, a "do not reintroduce" guard — in at most a few lines. No comments for self-evident cases (enabling a service, opening a port, persisting a state dir), no narrative essays, no restating upstream docs; the repo was deliberately de-essayed, keep it that way.
- **Feature-local inputs**: declare `flake-file.inputs.<name>.url` in the module that uses it, then `nix run .#write-flake`. Never edit `flake.nix` (generated; `check-flake-file` enforces sync).
- **Temporary fixes expire themselves**: every workaround for an upstream bug (overlay, pin, patch, flag) is wrapped in `lib.warnIf`/`warnIfNot` on the condition that would make it obsolete. In order of preference: nixpkgs reaching the fixed version (`versionAtLeast` — make the override inert then, never a downgrade, as in `pkgs/php.nix`); the upstream source no longer containing the broken code (`readFile` on `pkgs.path`/a flake input, as in `ipmi-fancontrol.nix`); and as a fallback, the package moving off the version the fix was written against (`version != "<x>"`). The message names the file and says what to check and what to delete. Under abort-on-warn a firing guard fails the build, so flake-bump stalls until someone either deletes the fix or, if it is still needed, bumps the guard. A bare "drop once upstream fixes it" comment is not enough.
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
  den.aspects.<x> = { includes = with den.aspects; [services.nginx services.netbird.client]; ... };
  ```
- **Recurring option shapes**: `port = mkOption {type = port; default = <n>;}` (published apps bind the default to a file-level `defaultPort` that their `netbird-service` entry also uses), `expose = mkOption {type = bool; default = false;}`, `mkEnableOption "..." // {default = true;}` for opt-out enables.
- **Impermanence**: aspects contribute paths declaratively via `cosmos.system.impermanence.persist.directories` (bare path string or `{directory, user, group}` attrset); activation is opt-in via the `core.impermanence` aspect.
- **Priority discipline**: `mkDefault` for overridable defaults; `mkForce` only for real overrides — and **never at the top level of an aspect body combined with facter** (den unwraps priority wrappers to classify content → infinite recursion). Wrap such modules in an inner `imports = [({...}: {...})]`; see the comment in `modules/den/hosts/pioneer.nix`. Same trap family: avoid config reads in host aspect top level (see `gaia.nix`'s `facter.detected.graphics.enable` comment), and never call `hasAspect` inside a plain `includes =` list.
- `mkForce` inside an `attrsOf` submodule doesn't do what you want for Hyprland's generated config; suppress bad output with `stylix.targets.<t>.disable` instead.
- **homeManager modules** are plain HM modules that freely read `osConfig` (same host); `lib.hm.dag` for ordering.
- **Wrapped programs** (tmux, yazi, oh-my-posh, zathura, foot via nix-wrapper-modules): the aspect defines `mk<prog> = pkgs: …`, exports it as `perSystem.packages.<prog>` and has home-manager install the same wrapper built against the host's pkgs. The wrapper is the config's source of truth, so home-manager writes no config for it and stylix can't reach it: theme it from the `cosmosStyling` module arg (`desktop/styling.nix`: scheme, `colors pkgs`, opacity, fonts), which stylix reads too. Host-specific additions layer onto the wrapper (`.wrap`) from the existing `cosmos.*` HM options.
- **nvim lives in launchpad** (`knot.lvdar.nl/did:plc:3l35i5iht5tqeoeqlfxzgkls`, a separate public flake: the nvim config, `nvim-<lang>` variants, shared devShells and templates). `home.nvim` builds `launchpad.lib.mkNvim` against the host's pkgs and layers on the fleet's theme, wayland and minuet endpoint; hosts install the language-free base, and a project's devshell brings the variant with its tools. Editor changes go to launchpad, then `nix flake update launchpad` here.
- **Cross-host data**, three tools, cheapest first:
  1. **Host entity facts** (`den.hosts.<sys>.<name>.meshAddress`, `.server`, `.users`, names): plain data, readable from any host or flake module without evaluating that host. Used for mesh IPs, host lists, deploy-rs nodes, ssh config.
  2. **Quirks** (`den.quirks.<q>` + a `pipe.collect`/`collectAll` policy included only by the consumer): producer aspects emit entries, the consumer gets the list as a module arg. `netbird-service` (gaia's netbird server), `kanidm-provision` (kanidm on endeavour), `scrape-target` (prometheus), `mesh-dns-record` (unbound). `collect` reaches same-system hosts only; `collectAll` also reaches pioneer. Keep payloads static or `{host, ...}:`; a `{config, ...}:` payload makes the consumer instantiate the producer host's whole config (comin evaluates on gaia), and config-dependent quirks cannot be chained.
  3. **Literals**, only for what no config or entity holds (e.g. netbird-proxy's embedded-client address, preference-ordered resolver lists). Comment them as hand-synced.
- Names: kebab-case aspect names matching their file; nested subdirs extend the namespace (`services/arr/*.nix` → `den.aspects.services.arr.radarr`).

## Important Files

- `flake.nix` — **generated, never edit**; header says so. `nixConfig.abort-on-warn = true`.
- `modules/den/hosts/gaia.nix` — the edge: NetBird control plane, `localVhosts`, oidc.idp. Published services are declared by their own aspects (`netbird-service` key).
- `modules/den/hosts/voyager.nix` — boot-time compositor specialisations (base/hyprland + niri as separate GRUB entries); `provides.lvdar` holds the user's host-specific home config.
- `modules/den/aspects/core/{sops,impermanence,impermanence-options,networking,users-base}.nix` — secrets, persistence, `edgeTerminated`, primary user.
- `modules/meta/{nixpkgs,formatter,pre-commit,devshell,deploy,wrappers}.nix` — flake machinery.
- `modules/den/hosts/_hw/<host>/disko.nix`, `_facter/<host>.facter.json` — declarative hardware; voyager's disko takes `{device}` as an argument.
- `.tangled/workflows/lint.yml` — the only CI (spindle): builds `checks.{treefmt,pre-commit,check-flake-file,default-shell}` with the nix-secrets stub override; does *not* run `nix flake check` wholesale.

## Runtime/Tooling Preferences

- Nix flake workflow only; no justfile, no scripts dir, no GitHub Actions. `.envrc` at root is `use flake`.
- `nixConfig.abort-on-warn = true`: **any nixpkgs/HM/den eval warning (deprecation etc.) is a hard build failure**, not a warning. Upgrades introducing deprecation warnings break the build. den tracks `main` and is bumped daily by flake-bump.
- Formatter set is fixed: alejandra (Nix) + deadnix + shfmt via treefmt (`modules/meta/formatter.nix`); `flake.nix`, `*.facter.json`, `*.lua` are excluded. deadnix strips lambda args that look unused, but den dispatches on arg *names* (`{host, ...}:` in policies/quirks): keep them with `# deadnix: skip` on the line directly above. `.pre-commit-config.yaml` is gitignored — hooks are flake-managed in `modules/meta/pre-commit.nix`.
- **`git add` new files before building** — the flake is a `git+file://` source, so unstaged files are invisible and produce confusing "option does not exist" errors.
- Secrets: sops-nix sourced from the private `nix-secrets` flake input over SSH (`git+ssh`). **The flake cannot be evaluated without access to that repo.** Machines without a key (build-gate, flake-bump, CI) build with `--override-input nix-secrets ./.tangled/nix-secrets-stub` (sound because `validateSopsFiles = false`).
- Git remotes: `origin` = the knot (`knot.lvdar.nl`, what comin watches), sole fetch URL, dual push URLs (knot + GitHub) — a partial push can desync the mirror. Pull before pushing; flake-bump commits on its own.
- `system.configurationRevision` is stamped from the git rev (`core/revision.nix`), so every commit changes every toplevel drvPath. To prove a refactor is a no-op, compare with it pinned: `nix eval --raw <ref>#nixosConfigurations.<h> --apply 'c: (c.extendModules {modules = [({lib, ...}: {system.configurationRevision = lib.mkForce "pinned";})];}).config.system.build.toplevel.drvPath'`.
- voyager is impermanent: `/tmp` and unpersisted home paths vanish on reboot. Keep scratch worktrees and notes under a persisted path (e.g. `~/dev`).

## Testing & QA

- No test framework, no coverage expectations. Verification = the change evaluates and builds (`nix build .#nixosConfigurations.<host>...`) and, for the fleet, build-gate turning it green before comin touches a host.
- `nix flake check` covers treefmt, pre-commit hooks, deploy-rs checks (`deploy-activate` is slow), `check-flake-file` and the default-shell build.
- CI on the spindle is deliberately fast-feedback: the four cheap checks with `--accept-flake-config` (abort-on-warn applies) and the secrets stub.
- Practical smoke checks when debugging publishing/ingress: `curl -I` against the public name (probes DNS → edge TLS → netbird-proxy → app); `git log deploy..main` shows what has not passed the gate yet.
