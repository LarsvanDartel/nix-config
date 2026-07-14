# Formatting via treefmt-nix (replaces the alejandra/deadnix/shfmt part of the
# old checks.nix). Provides `nix fmt` and a `checks.<sys>.treefmt`.
{inputs, ...}: {
  flake-file.inputs.treefmt-nix = {
    url = "github:numtide/treefmt-nix";
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
