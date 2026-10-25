# Portable, stylix-themed wrapped packages via sini/hm-wrapper-modules,
# exposed as `packages.<system>.<name>`; the home-manager install stays the
# daily driver. Drives the library directly: upstream's autoWrap can't work
# here (module-classes.nix wraps every flake.modules.* entry in an attrs,
# defeating isWrappable).
{
  inputs,
  den,
  lib,
  ...
}: let
  hm = builtins.mapAttrs (_: a: a.homeManager) den.aspects.home;

  # hm-adapter.nix still defines `extraPackages`, which nix-wrapper-modules
  # removed (renamed `runtimePkgs`); even under a false mkIf that is an
  # undeclared option, so every wrap fails. The file is self-contained, so
  # rename it at eval time.
  adapterSrc = builtins.readFile "${inputs.hm-wrapper-modules}/lib/hm-adapter.nix";
  staleLine = "extraPackages = lib.mkIf (extractedExtraPackages != [ ]) extractedExtraPackages;";
  patchedAdapter = import (builtins.toFile "hm-adapter.nix" (builtins.replaceStrings [staleLine] ["runtimePkgs = lib.mkIf (extractedExtraPackages != [ ]) extractedExtraPackages;"] adapterSrc)) {
    inherit lib;
    wlib = inputs.nix-wrapper-modules.lib;
  };
  wlib =
    lib.warnIfNot (lib.hasInfix staleLine adapterSrc) ''
      modules/meta/hm-wrappers.nix: hm-wrapper-modules' hm-adapter.nix no longer sets `extraPackages`.
      Delete adapterSrc/staleLine/patchedAdapter and use inputs.hm-wrapper-modules.lib directly.
    ''
    (inputs.hm-wrapper-modules.lib // {inherit (patchedAdapter) wrapHomeModule;});

  baseModules = [hm.wrapper-stylix hm.wrapper-stubs];

  stateVersion = "26.11";

  # foot is intentionally omitted — its home aspect reads desktop font
  # options that don't exist in an isolated wrap eval.
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
    "htop"
    "fzf"
    "zathura"
    "starship"
    "alacritty"
    "ranger"
  ];

  # wrapper-stylix has autoEnable off; enabling only the program's own target
  # keeps desktop theming (GTK/KDE/…) out of the closure.
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

  mkPackage = pkgs: name: program: let
    base = wlib.wrapHomeModule {
      inherit pkgs stateVersion;
      inherit (program) homeModules;
      home-manager = inputs.home-manager;
      programName = name;
    };
  in
    base.wrap ({config, ...}: {
      imports = [wlib.modules.bwrapConfig];
      bwrapConfig.binds.ro = wlib.mkBinds base.passthru.hmAdapter;
      env.XDG_CONFIG_HOME = lib.mkIf config.bwrapConfig.enable (lib.mkForce null);
    });
in {
  # flake-file can't URL-pin a transitive input, so nix-wrapper-modules stays
  # top-level for hm-wrapper-modules to follow.
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

  # git is omitted too — den's home.git signing reads the host-specific
  # cosmos.user.home, absent in an isolated wrap.
  perSystem = {pkgs, ...}: {
    packages = lib.mapAttrs (mkPackage pkgs) (lib.genAttrs wrapNames mkProgram);
  };
}
