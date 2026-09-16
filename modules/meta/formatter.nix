# Formatting via treefmt-nix: provides `nix fmt` and a `checks.<sys>.treefmt`.
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
      # flake.nix is formatted by flake-file (write-flake); treefmt off it so
      # the two don't fight.
      "flake.nix"
      "*hardware-configuration.nix"
      "*.facter.json"
      "*.png"
      "*.jpg"
      "*.lua"
    ];
  };
}
