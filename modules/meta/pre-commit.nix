# pre-commit — git-hooks flakeModule providing checks.<sys>.pre-commit and the devshell hook installer.
{inputs, ...}: {
  flake-file.inputs.pre-commit-hooks = {
    url = "github:cachix/git-hooks.nix";
    inputs.nixpkgs.follows = "nixpkgs";
  };

  imports = [inputs.pre-commit-hooks.flakeModule];

  perSystem = {
    config,
    pkgs,
    ...
  }: let
    # Vendored oisd blocklists must stay byte-for-byte upstream, and a patch's
    # blank context lines are a single space; keep every rewriting hook off them.
    vendored = ["\\.unbound$" "\\.patch$"];
  in {
    pre-commit.settings.hooks = {
      check-added-large-files = {
        enable = true;
        excludes = ["\\.png" "\\.jpg"] ++ vendored;
      };
      check-case-conflicts.enable = true;
      check-executables-have-shebangs.enable = true;
      check-shebang-scripts-are-executable.enable = false;
      check-merge-conflicts.enable = true;
      detect-private-keys.enable = true;
      fix-byte-order-marker = {
        enable = true;
        excludes = vendored;
      };
      mixed-line-endings = {
        enable = true;
        excludes = vendored;
      };
      trim-trailing-whitespace = {
        enable = true;
        excludes = vendored;
      };
      end-of-file-fixer = {
        enable = true;
        excludes = vendored;
      };

      forbid-submodules = {
        enable = true;
        name = "forbid submodules";
        description = "forbids any submodules in the repository";
        language = "fail";
        entry = "submodules are not allowed in this repository:";
        types = ["directory"];
      };

      comment-policy = {
        enable = true;
        name = "comment policy";
        description = "one-line headers, comment blocks of at most two lines, no dates, live docs pointers";
        entry = "${pkgs.python3.interpreter} ${./_comment-policy.py}";
        types_or = ["nix" "python" "shell" "yaml"];
        excludes = ["^flake\\.nix$"];
      };

      shellcheck = {
        enable = true;
        excludes = [
          "^\\.envrc$"
        ];
      };

      treefmt = {
        enable = true;
        packageOverrides.treefmt = config.treefmt.build.wrapper;
      };
    };
  };
}
