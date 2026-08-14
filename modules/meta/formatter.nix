# Formatting via treefmt-nix (replaces the alejandra/deadnix/shfmt part of the
# old checks.nix). Provides `nix fmt` and a `checks.<sys>.treefmt`.
{inputs, ...}: {
  # Pinned to numtide/treefmt-nix#531 (qowoz:eval-warning), *not* upstream main.
  #
  # treefmt-nix's module-options.nix still reads `pkgs.stdenv.isDarwin`, which
  # recent nixpkgs deprecates. With this repo's `abort-on-warn = true` that is
  # not a warning, it is a build failure — so `checks.<sys>.treefmt` stopped
  # evaluating entirely the moment the lock moved forward, taking `nix flake
  # check` and the lint workflow with it. Nothing here caused it and no pin of
  # treefmt-nix avoids it: the deprecation is on the nixpkgs side.
  #
  # #531 is the one-line fix (isDarwin -> hostPlatform.isDarwin), approved by a
  # maintainer but unmerged. Pinned to the PR head by full SHA, and verified to
  # differ from upstream by exactly those two lines and nothing else.
  #
  # REVERT THIS to `github:numtide/treefmt-nix` once #531 lands — a fork pin is
  # a supply-chain edge this repo should not keep for convenience.
  flake-file.inputs.treefmt-nix = {
    url = "github:qowoz/treefmt-nix/7859a27edf53b907acd6115efbc52e20ba79ddb5";
    inputs.nixpkgs.follows = "nixpkgs";
  };

  imports = [inputs.treefmt-nix.flakeModule];

  perSystem.treefmt = {
    projectRootFile = "flake.nix";

    programs = {
      alejandra.enable = true;
      deadnix = {
        enable = true;
        no-lambda-arg = true;
      };
      shfmt.enable = true;
    };

    settings.global.excludes = [
      # flake.nix is generated + formatted by flake-file (write-flake); keep
      # treefmt off it so the two don't fight over style.
      "flake.nix"
      "*hardware-configuration.nix"
      "*.facter.json"
      "*.png"
      "*.jpg"
      "*.lua"
    ];
  };
}
