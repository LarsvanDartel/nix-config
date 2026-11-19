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
      # Explicit: treefmt-nix dropped these defaults (-i 2 -s), after which
      # shfmt follows .editorconfig's 4 and reindents every script.
      shfmt = {
        enable = true;
        indent_size = 2;
        simplify = true;
      };
    };

    settings.global.excludes = [
      # flake.nix is formatted by flake-file (write-flake); treefmt off it so
      # the two don't fight.
      "flake.nix"
      "*.facter.json"
      "*.png"
      "*.jpg"
      "*.lua"
    ];
  };
}
