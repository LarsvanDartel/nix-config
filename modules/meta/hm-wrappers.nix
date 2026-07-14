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
  config,
  lib,
  ...
}: let
  hm = config.flake.modules.homeManager;

  # Tier 1 programs wrapped as portable, stylix-themed packages. Grown as
  # per-program modules are split out of the common/desktop aggregates.
  wrapNames = [
    # split out of the common/desktop aggregates
    "bat"
    "foot"
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
    foot = "foot";
    btop = "btop";
    yazi = "yazi";
    zathura = "zathura";
    tmux = "tmux";
    lazygit = "lazygit";
    starship = "starship";
    alacritty = "alacritty";
  };

  # Identity injected into the git wrapper (no host-specific signing in a portable
  # build); mirrors the deployment values in home/profiles/common.nix.
  gitIdentity = {
    user = "LarsvanDartel";
    email = "larsvandartel73@gmail.com";
  };

  mkProgram = n: {
    homeModules =
      [hm.${n}]
      ++ lib.optional (themedTargets ? ${n}) {stylix.targets.${themedTargets.${n}}.enable = true;};
  };
in {
  # Pin `nix-wrapper-modules` to the last rev BEFORE upstream renamed
  # `extraPackages`→`runtimePkgs` (BirdeeHub#540, 2026-05-19), and have
  # hm-wrapper-modules follow it. The pinned adapter still calls `extraPackages`;
  # on any newer rev that emits a deprecation warning which `abort-on-warn` turns
  # fatal (breaking `nix build`/`flake check` of the wrappers). 3abe4c9a has every
  # API the adapter needs, warning-free. (flake-file can't URL-pin a transitive
  # input, so nix-wrapper-modules is a top-level input followed by hm-wrapper-
  # modules.) Revisit before 2026-08-31, when `extraPackages` is removed and
  # hm-wrapper-modules must migrate to `runtimePkgs`.
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
      url = "github:BirdeeHub/nix-wrapper-modules/f318ea7274683aa1af36cff22f7b40420807324a";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  imports = [inputs.hm-wrapper-modules.flakeModules.default];

  hmWrappers = {
    home-manager = inputs.home-manager;
    stateVersion = "26.11";

    # Theming applied to every wrapped program.
    baseModules = [hm.wrapper-stylix];
  };

  perSystem = _: {
    hmWrappers.programs =
      (lib.genAttrs wrapNames mkProgram)
      // {
        # Tier 2: git with identity injected via extraSpecialArgs.
        git = (mkProgram "git") // {extraSpecialArgs.gitIdentity = gitIdentity;};
      };
  };
}
