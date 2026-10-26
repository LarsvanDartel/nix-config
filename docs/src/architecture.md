# Architecture

## Evaluation flow

Generated `flake.nix` → `mkFlake` + `import-tree ./modules` → every module auto-loads → den assembles `nixosConfigurations` from aspects → each host builds its own `pkgs` in `core.nixpkgs` (stable + unstable + NUR + `inputs.self.overlays.default`). `modules/meta/nixpkgs.nix` is perSystem's pkgs only (packages, devshell).

## Composition model

Lives in `modules/den/`.

- **Aspect** = the unit of configuration: `den.aspects.<group>.<name>` with any of `includes` (other aspects), `nixos` (NixOS module), `homeManager` (HM module), `provides.*` (cross-entity edges, below), and quirk keys (`kanidm-provision`, `netbird-service`, `scrape-target`, `mesh-dns-record`).
- **Where config lands**: host scope delivers only `nixos`; a `homeManager` key on a host-included aspect is **silently dropped**. Host → its users: `provides.to-users` (e.g. `services.eduvpn`, `roles.gaming`, `desktop.hyprland`, `desktop.styling`, `services.netbird-gewis`). User → its hosts: `provides.to-hosts` (e.g. `home.kde-connect`, `home.catt`, `home.taskwarrior`). Never a plain `nixos` key on a user-scope aspect: that only works through den bug #694. Host-specific user config goes in `den.aspects.<host>.provides.<user>`, not a host child named after the user.
- **Roles** (`modules/den/aspects/roles/`): `default` (every host, `den.schema.host.includes`), `server` (via the `server-role` policy when the host entity has `server = true`), `desktop`, `desktop-home`, `gaming`, `home-base` (every user, `den.schema.user.includes`).
- **Hosts** (`modules/den/hosts/<host>.nix`) register `den.hosts.<arch>.<host> = { users.<user> = {}; meshAddress; server; deployAddress; }` (facts declared in `modules/den/schema.nix`) and define a per-host aspect stacking roles + individual aspects + hardware imports. Every host has exactly one user (asserted); `cosmos.user.name` is derived from it.
- `modules/den/defaults.nix`: what every host/user gets (batteries, `core.nixpkgs`, `core.home-manager`, HM class for all users, `roles.default` per host, user-shell zsh + `roles.home-base` per user).
- Custom options live under **`cosmos.*`**, declared by whichever aspect owns the feature. Frequently used: `cosmos.system.impermanence.persist.*`, `cosmos.networking.edgeTerminated`, `cosmos.services.*`, `cosmos.user.*`.
- **Local packages**: each `modules/pkgs/*.nix` self-registers into the `nixpkgs.overlays` aggregator option; `modules/den/overlays.nix` composes `flake.overlays.default`, consumed by hosts via `inputs.self.overlays.default`.

## Key directories

|Path|Purpose|
|---|---|
|`modules/meta/`|Flake-level infra: perSystem nixpkgs, treefmt, pre-commit, devshell, deploy-rs nodes (from `den.hosts`), flake-file, `cosmosLib` helpers, the docs build|
|`modules/pkgs/`|Local packages, each self-registering into the overlays aggregator|
|`modules/den/aspects/`|The configuration itself (~200 files): `core/ desktop/ hardware/ home/ roles/ services/`|
|`modules/den/hosts/`|One aspect-bearing file per host + `_hw/` (disko) + `_facter/` (hardware reports)|
|`modules/den/users/`|User aspects: `lvdar.nix` (the `nixos` server user needs none)|
|`modules/den/schema.nix`|Host entity facts (`meshAddress`, `server`, `deployAddress`) + the `server-role` policy|
|`modules/den/defaults.nix`|Every-host/user baseline|
|`modules/den/deployment.nix`|Facts about *this* deployment, applied to every host via `den.default.nixos` — values that would otherwise hide as option defaults inside aspects. Only options that exist on *every* host; anything narrower goes in that host's file|
|`docs/`|This book (`nix build .#docs`)|
|`.tangled/`|Spindle CI workflow (`lint.yml`) + `nix-secrets-stub` used by build-gate/flake-bump/CI|

## `_`-prefixed files

**`_`-prefixed files/dirs are skipped by import-tree** — they hold plain modules/assets imported explicitly by the aspect that needs them (e.g. `aspects/home/desktop/_styling/` → `styling.nix` does `homeManager.imports = [./_styling]`). Recurring reason: specialisation bodies are plain NixOS modules that cannot `include` den aspects, so shared content lives in parameterized factories (e.g. `_niri/system.nix`) called from both the aspect and the specialisation.

## Cross-host data

Three tools, cheapest first:

1. **Host entity facts** (`den.hosts.<sys>.<name>.meshAddress`, `.server`, `.users`, names): plain data, readable from any host or flake module without evaluating that host. Used for mesh IPs, host lists, deploy-rs nodes, ssh config.
2. **Quirks** (`den.quirks.<q>` + a `pipe.collect`/`collectAll` policy included only by the consumer): producer aspects emit entries, the consumer gets the list as a module arg. `netbird-service` (gaia's netbird server), `kanidm-provision` (kanidm on endeavour), `scrape-target` (prometheus), `mesh-dns-record` (unbound). `collect` reaches same-system hosts only; `collectAll` also reaches pioneer. Keep payloads static or `{host, ...}:`; a `{config, ...}:` payload makes the consumer instantiate the producer host's whole config (comin evaluates on gaia), and config-dependent quirks cannot be chained.
3. **Literals**, only for what no config or entity holds (e.g. netbird-proxy's embedded-client address, preference-ordered resolver lists). Comment them as hand-synced.
