# Portable, stylix-themed wrapped packages via sini/hm-wrapper-modules.
#
# Evaluates each program's real home-manager module (composed with the
# `wrapper-stylix` base module) and bwraps the themed output into a standalone
# derivation, exposed as `packages.<system>.<name>`. This is an *augmenting*
# catalog: the normal home-manager install stays the authoritative daily driver;
# these are extra `nix run/build .#<prog>` outputs.
#
# We register programs explicitly via a curated `wrapNames` list rather than
# `autoWrap`. `modules/meta/module-classes.nix` wraps every `flake.modules.*`
# entry in an attrs (`{key; _file; imports;}`), which defeats hm-wrapper's
# arg-sniffing `isWrappable` (it would treat every aggregate as wrappable), so an
# explicit list is safer than a fragile all-encompassing `exclude`. Programs that
# need injected context (e.g. git identity) register themselves in their own
# feature file with `extraSpecialArgs`.
{
  inputs,
  den,
  lib,
  ...
}: let
  # Bridge to den: each wrapped program's home module is the den aspect's
  # homeManager class content (den.aspects.home.<n>.homeManager).
  hm = builtins.mapAttrs (_: a: a.homeManager) den.aspects.home;

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
      [hm.${n}]
      ++ lib.optional (themedTargets ? ${n}) {stylix.targets.${themedTargets.${n}}.enable = true;};
  };
in {
  # nix-wrapper-modules used to be pinned to the last rev before upstream renamed
  # `extraPackages`→`runtimePkgs` (BirdeeHub#540, 2026-05-19), because newer revs
  # warn on the old name and `abort-on-warn` makes that fatal. The pin is gone:
  # the warning only fires when `extraPackages` is non-empty, and the adapter
  # only fills it from a wrapped module's `home.packages`, which none of the
  # programs below declare. Verified by building voyager — both specialisations,
  # so niri and noctalia too — under `--option abort-on-warn true`, clean.
  #
  # That is a reprieve, not a fix, and it expires on 2026-08-31.
  #
  # On that date `extraPackages` is *removed*, and hm-wrapper-modules
  # (lib/hm-adapter.nix:401) defines it unconditionally as
  # `lib.mkIf (extracted != []) extracted`. A `mkIf false` on an option that does
  # not exist is still a hard "unknown option" error — checked, it does not get
  # filtered out first — so this breaks whether or not anything uses the value,
  # and `extractPackages = false` does not help either: it empties the list
  # without removing the definition.
  #
  # Nobody upstream is going to fix it. hm-wrapper-modules' last commit is
  # 2026-03-26 and there is no PR or issue for the rename. The choice is ours:
  # fork the adapter for the one-line change, re-pin nix-wrapper-modules and
  # accept a frozen wrapper lib against a moving nixpkgs, or drop the adapter and
  # keep only the direct `wrappers.<x>.wrap` calls (niri, noctalia), which do not
  # touch it.
  #
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

  imports = [inputs.hm-wrapper-modules.flakeModules.default];

  hmWrappers = {
    home-manager = inputs.home-manager;
    stateVersion = "26.11";

    # Theming + cross-cutting option stubs applied to every wrapped program.
    baseModules = [hm.wrapper-stylix hm.wrapper-stubs];
  };

  # NOTE: git is omitted too — den's home.git bakes in ssh commit signing that
  # reads cosmos.user.home (host-specific), which isn't portable/present in an
  # isolated wrap. The deployed git (on every host) is unaffected.
  perSystem = _: {
    hmWrappers.programs = lib.genAttrs wrapNames mkProgram;
  };
}
