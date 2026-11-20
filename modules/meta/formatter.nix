# formatter — treefmt-nix: `nix fmt` and `checks.<system>.treefmt`.
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
      # Keep -i 2 -s explicit: without them shfmt follows .editorconfig's 4 and reindents every script.
      shfmt = {
        enable = true;
        indent_size = 2;
        simplify = true;
      };
    };

    settings.global.excludes = [
      # flake-file (write-flake) formats flake.nix; treefmt stays off it so the two don't fight.
      "flake.nix"
      "*.facter.json"
      "*.png"
      "*.jpg"
      "*.lua"
    ];
  };
}
