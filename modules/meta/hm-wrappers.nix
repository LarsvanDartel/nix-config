# Portable, stylix-themed wrapped packages via sini/hm-wrapper-modules.
#
# Evaluates each program's real home-manager module (composed with the
# `wrapper-stylix` base module) and bwraps the themed output into a standalone
# derivation, exposed as `packages.<system>.<name>`. This is an *augmenting*
# catalog: the normal home-manager install stays the authoritative daily driver;
# these are extra `nix run/build .#<prog>` outputs.
#
# We drive hm-wrapper-modules' library directly instead of importing its
# flake module -- see the comment on `mkPackage` for why. That also means the
# catalog is a curated `wrapNames` list rather than the flake module's
# `autoWrap`, which would not have worked here anyway:
# `modules/meta/module-classes.nix` wraps every `flake.modules.*` entry in an
# attrs (`{key; _file; imports;}`), defeating the arg-sniffing `isWrappable`
# that auto-discovery filters on -- it would treat every aggregate as
# wrappable.
{
  inputs,
  den,
  lib,
  ...
}: let
  # Bridge to den: each wrapped program's home module is the den aspect's
  # homeManager class content (den.aspects.home.<n>.homeManager).
  hm = builtins.mapAttrs (_: a: a.homeManager) den.aspects.home;

  # The full nix-wrapper-modules API plus this flake's HM adapter, the same
  # value its flakeModules.default is built from.
  wlib = inputs.hm-wrapper-modules.lib;

  # Theming + cross-cutting option stubs applied to every wrapped program.
  baseModules = [hm.wrapper-stylix hm.wrapper-stubs];

  stateVersion = "26.11";

  # Tier 1 programs wrapped as portable, stylix-themed packages. Grown as
  # per-program modules are split out of the common/desktop aggregates.
  # NOTE: foot is intentionally omitted — its home aspect reads the desktop
  # styling font options, which don't exist in an isolated wrap eval.
  wrapNames = [
    "bat"
    "mpv"
    "btop"
    "lazygit"
    "ripgrep"
    "fd"
    "tmux"
    "eza"
    "direnv"
    "zoxide"
    "yazi"
    "oh-my-posh"
    # already standalone named modules
    "htop"
    "fzf"
    "zathura"
    "starship"
    "alacritty"
    "ranger"
  ];

  # program -> stylix target name, for programs stylix can theme. The base module
  # (wrapper-stylix) has autoEnable off, so we turn on just the relevant target
  # per program to keep desktop theming (GTK/KDE/blender/…) out of the closure.
  # Programs with no stylix target (or that read colors directly, like fzf) are
  # simply not listed.
  themedTargets = {
    bat = "bat";
    btop = "btop";
    yazi = "yazi";
    zathura = "zathura";
    tmux = "tmux";
    lazygit = "lazygit";
    starship = "starship";
    alacritty = "alacritty";
  };

  mkProgram = n: {
    homeModules =
      baseModules
      ++ [hm.${n}]
      ++ lib.optional (themedTargets ? ${n}) {stylix.targets.${themedTargets.${n}}.enable = true;};
  };

  # The upstream flake module's job, done here instead. parts.nix generates
  # `perSystem.packages` by calling `wlib.wrapHomeModule` with its default
  # `extractPackages = true`, which routes each module's `home.packages` into
  # the wrapper's *deprecated* `extraPackages`. That option warns when non-empty
  # — and `abort-on-warn` makes a warning fatal — so every program whose HM
  # module puts anything in `home.packages` (which `programs.<x>.enable`
  # generally does, with the program itself) fails to evaluate. It is removed
  # outright on 2026-08-31.
  #
  # parts.nix exposes no way to reach `extractPackages`, and upstream is not
  # going to add one: hm-wrapper-modules' last commit is 2026-03-26 and there is
  # no PR or issue for the rename. So we skip parts.nix — 30 lines, reproduced
  # below — and call the same public `wlib.wrapHomeModule` ourselves with
  # extraction off, feeding `home.packages` into `runtimePkgs`, the successor
  # option, by hand. Same packages on the wrapper's PATH, none of the deprecated
  # surface.
  hmEval = pkgs: homeModules:
    (inputs.home-manager.lib.homeManagerConfiguration {
      inherit pkgs;
      modules =
        homeModules
        ++ [
          {
            home.username = "wrapper-user";
            home.homeDirectory = "/homeless-shelter";
            home.stateVersion = stateVersion;
          }
        ];
    })
    .config;

  mkPackage = pkgs: name: program: let
    base = wlib.wrapHomeModule {
      inherit pkgs stateVersion;
      inherit (program) homeModules;
      home-manager = inputs.home-manager;
      programName = name;
      extractPackages = false;
    };
  in
    base.wrap ({config, ...}: {
      imports = [wlib.modules.bwrapConfig];
      bwrapConfig.binds.ro = wlib.mkBinds base.passthru.hmAdapter;
      env.XDG_CONFIG_HOME = lib.mkIf config.bwrapConfig.enable (lib.mkForce null);

      # The adapter already evaluated exactly this, and hands it back as
      # `base.passthru.hmAdapter.hmConfig` — but reading anything under
      # `passthru` merges it through nix-wrapper-modules' `attrsRecursive`
      # type, whose `lazyAttrsOf` is documented as "less lazy": it forces
      # `optionalValue` for *every* key it descends. Walking a whole
      # home-manager config that way reaches `home.sessionVariableSetter`,
      # which home-manager removed, and `mkRemovedOptionModule` throws the
      # moment its value is read. So this evaluates the modules a second time
      # rather than touching passthru. It costs an extra HM eval per wrapped
      # program and is the reason `hmEval` exists.
      runtimePkgs = (hmEval pkgs program.homeModules).home.packages;
    });
in {
  # (flake-file can't URL-pin a transitive input, so nix-wrapper-modules stays a
  # top-level input that hm-wrapper-modules follows.)
  flake-file.inputs = {
    hm-wrapper-modules = {
      url = "github:sini/hm-wrapper-modules";
      inputs = {
        home-manager.follows = "home-manager";
        nixpkgs.follows = "nixpkgs";
        nix-wrapper-modules.follows = "nix-wrapper-modules";
      };
    };
    nix-wrapper-modules = {
      url = "github:BirdeeHub/nix-wrapper-modules";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  # NOTE: git is omitted too — den's home.git bakes in ssh commit signing that
  # reads cosmos.user.home (host-specific), which isn't portable/present in an
  # isolated wrap. The deployed git (on every host) is unaffected.
  perSystem = {pkgs, ...}: {
    packages = lib.mapAttrs (mkPackage pkgs) (lib.genAttrs wrapNames mkProgram);
  };
}
