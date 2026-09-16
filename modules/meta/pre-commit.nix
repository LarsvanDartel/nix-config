# git-hooks (pre-commit) as a flakeModule: provides `checks.<sys>.pre-commit`
# and the devshell installation script; the treefmt hook runs formatter.nix.
{inputs, ...}: {
  flake-file.inputs.pre-commit-hooks = {
    url = "github:cachix/git-hooks.nix";
    inputs.nixpkgs.follows = "nixpkgs";
  };

  imports = [inputs.pre-commit-hooks.flakeModule];

  perSystem = {config, ...}: let
    # The vendored oisd blocklists — byte-for-byte what oisd serves (the point
    # of the snapshot; services/unbound.nix has the reasoning). Excluded from
    # every hook that would rewrite them: end-of-file-fixer failed on them
    # outright, and any "fix" would break the upstream match.
    vendored = ["\\.unbound$"];
  in {
    pre-commit.settings.hooks = {
      # ========== General ==========
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

      # ========== shellscripts ==========
      shellcheck = {
        enable = true;
        excludes = [
          "^\\.envrc$"
        ];
      };

      # ========== nix (formatting delegated to treefmt) ==========
      treefmt = {
        enable = true;
        packageOverrides.treefmt = config.treefmt.build.wrapper;
      };
    };
  };
}
