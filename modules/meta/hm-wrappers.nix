# Portable, stylix-themed wrapped packages via sini/hm-wrapper-modules: each
# program's real home-manager module, composed with the wrapper-stylix base,
# bwrapped into a standalone derivation exposed as `packages.<system>.<name>`.
# Augmenting catalog — the normal home-manager install stays the daily driver.
#
# Drives the library directly instead of the upstream flake module: autoWrap
# would not work here anyway — module-classes.nix wraps every flake.modules.*
# entry in an attrs, defeating the arg-sniffing isWrappable. See the comment
# on hmEval for the parts.nix side of that decision.
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

  # Tier 1 programs wrapped as portable, stylix-themed packages.
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

  # program -> stylix target name. wrapper-stylix has autoEnable off; only
  # the relevant target is enabled per program, keeping desktop theming
  # (GTK/KDE/blender/…) out of the closure. No entry = no stylix target.
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

  # The upstream flake module's job, done here instead. parts.nix calls
  # wrapHomeModule with the default extractPackages = true, routing
  # home.packages into the deprecated `extraPackages` — a warning, fatal
  # under abort-on-warn, for every program whose HM module puts anything in
  # home.packages (which `programs.<x>.enable` generally does). It is removed
  # outright on 2026-08-31, and parts.nix exposes no way to reach the flag
  # (upstream is dormant), so we call the same public wrapHomeModule
  # ourselves with extraction off, feeding home.packages into `runtimePkgs`,
  # the successor option, by hand.
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

      # Re-evaluated instead of read from passthru: nix-wrapper-modules'
      # attrsRecursive (lazyAttrsOf, documented "less lazy") forces
      # optionalValue for every key it descends, and walking a whole
      # home-manager config that way reaches the removed
      # home.sessionVariableSetter, which throws on read. Costs an extra HM
      # eval per program — the reason hmEval exists.
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
