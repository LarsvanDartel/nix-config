# git-hooks (pre-commit) as a flakeModule: the git-side hooks from the old
# checks.nix, plus a treefmt hook that runs the treefmt config (formatter.nix).
# Provides `checks.<sys>.pre-commit` and the devshell installation script.
{inputs, ...}: {
  flake-file.inputs.pre-commit-hooks = {
    url = "github:cachix/git-hooks.nix";
    inputs.nixpkgs.follows = "nixpkgs";
  };

  imports = [inputs.pre-commit-hooks.flakeModule];

  perSystem = {config, ...}: let
    # The vendored oisd blocklists — 12 MB and 22 MB of sorted domains, about
    # 4.8 MB compressed. They are byte-for-byte what oisd serves, and that is
    # the point: services/unbound.nix explains why a snapshot in git beats a
    # flake input pointing at a URL that changes daily, and `update-blocklists`
    # replaces them wholesale.
    #
    # Excluded from every hook that would *rewrite* them, not just the size
    # check. end-of-file-fixer failed on them outright, and had it been allowed
    # to "fix" the files they would no longer match upstream — so every refresh
    # would produce a spurious diff and the snapshot would stop being one.
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
