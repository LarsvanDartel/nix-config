# Conventions

## Code

- **Commits**: conventional-commit style, lowercase, imperative, explaining the *why* (`fix(netbird): move the OIDC callbacks off hash routes`).
- **Every file opens with a `# <name> — <what it is>` purpose comment**. Beyond that, comments earn their place by preventing a future mistake: a trap, a security decision, a hand-synced cross-host value, a packaging pin, a "do not reintroduce" guard — in at most a few lines. No comments for self-evident cases (enabling a service, opening a port, persisting a state dir), no narrative essays, no restating upstream docs; the repo was deliberately de-essayed, keep it that way.
- **Feature-local inputs**: declare `flake-file.inputs.<name>.url` in the module that uses it, then `nix run .#write-flake`. Never edit `flake.nix` (generated; `check-flake-file` enforces sync).
- **Temporary fixes expire themselves**: every workaround for an upstream bug (overlay, pin, patch, flag) is wrapped in `lib.warnIf`/`warnIfNot` on the condition that would make it obsolete. In order of preference: nixpkgs reaching the fixed version (`versionAtLeast` — make the override inert then, never a downgrade, as in `pkgs/suwayomi-server.nix`); the upstream source no longer containing the broken code (`readFile` on `pkgs.path`/a flake input, as in `stalwart.nix`); and as a fallback, the package moving off the version the fix was written against (`version != "<x>"`). The message names the file and says what to check and what to delete. Under abort-on-warn a firing guard fails the build, so flake-bump stalls until someone either deletes the fix or, if it is still needed, bumps the guard. A bare "drop once upstream fixes it" comment is not enough.
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
- `mkForce` inside an `attrsOf` submodule doesn't reliably override a stylix target's generated config; suppress bad output with `stylix.targets.<t>.disable` instead.
- **homeManager modules** are plain HM modules that freely read `osConfig` (same host); `lib.hm.dag` for ordering.
- **Wrapped programs** (tmux, yazi, oh-my-posh, zathura, foot via nix-wrapper-modules): the aspect defines `mk<prog> = pkgs: …`, exports it as `perSystem.packages.<prog>` and has home-manager install the same wrapper built against the host's pkgs. The wrapper is the config's source of truth, so home-manager writes no config for it and stylix can't reach it: theme it from the `cosmosStyling` module arg (`desktop/styling.nix`: scheme, `colors pkgs`, opacity, fonts), which stylix reads too. Host-specific additions layer onto the wrapper (`.wrap`) from the existing `cosmos.*` HM options.
- **nvim lives in launchpad** (`knot.lvdar.nl/did:plc:3l35i5iht5tqeoeqlfxzgkls`, a separate public flake: the nvim config, `nvim-<lang>` variants, shared devShells and templates). `home.nvim` builds `launchpad.lib.mkNvim` against the host's pkgs and layers on the fleet's theme, wayland and minuet endpoint; hosts install the language-free base, and a project's devshell brings the variant with its tools. Editor changes go to launchpad, then `nix flake update launchpad` here.
- Names: kebab-case aspect names matching their file; nested subdirs extend the namespace (`services/arr/*.nix` → `den.aspects.services.arr.radarr`).

## Tooling

- Nix flake workflow only; no justfile, no scripts dir, no GitHub Actions. `.envrc` at root is `use flake`.
- `nixConfig.abort-on-warn = true`: **any nixpkgs/HM/den eval warning (deprecation etc.) is a hard build failure**, not a warning. Upgrades introducing deprecation warnings break the build. den tracks `main` and is bumped daily by flake-bump.
- Formatter set is fixed: alejandra (Nix) + deadnix + shfmt via treefmt (`modules/meta/formatter.nix`); `flake.nix`, `*.facter.json`, `*.lua` are excluded. deadnix strips lambda args that look unused, but den dispatches on arg *names* (`{host, ...}:` in policies/quirks): keep them with `# deadnix: skip` on the line directly above. `.pre-commit-config.yaml` is gitignored — hooks are flake-managed in `modules/meta/pre-commit.nix`.
- **`git add` new files before building** — the flake is a `git+file://` source, so unstaged files are invisible and produce confusing "option does not exist" errors.
- Git remotes: `origin` = the knot (`knot.lvdar.nl`, what comin watches), sole fetch URL, dual push URLs (knot + GitHub) — a partial push can desync the mirror. Pull before pushing; flake-bump commits on its own.
- voyager is impermanent: `/tmp` and unpersisted home paths vanish on reboot. Keep scratch worktrees and notes under a persisted path (e.g. `~/dev`).

## Important files

- `flake.nix` — **generated, never edit**; header says so. `nixConfig.abort-on-warn = true`.
- `modules/den/hosts/gaia.nix` — the edge: NetBird control plane, `localVhosts`, oidc.idp. Published services are declared by their own aspects (`netbird-service` key).
- `modules/den/hosts/voyager.nix` — niri base desktop plus the Umbriel boot-time specialisation (separate GRUB entry); `provides.lvdar` holds the user's host-specific home config.
- `modules/den/aspects/core/{sops,impermanence,impermanence-options,networking,users-base}.nix` — secrets, persistence, `edgeTerminated`, primary user.
- `modules/meta/{nixpkgs,formatter,pre-commit,devshell,deploy,wrappers,docs}.nix` — flake machinery.
- `modules/den/hosts/_hw/<host>/disko.nix`, `_facter/<host>.facter.json` — declarative hardware; voyager's disko takes `{device}` as an argument.
- `.tangled/workflows/lint.yml` — the only CI (spindle): builds `checks.{treefmt,pre-commit,check-flake-file,default-shell,docs}` with the nix-secrets stub override; does *not* run `nix flake check` wholesale.
