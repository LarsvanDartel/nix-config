# git-hooks (pre-commit) as a flakeModule: the git-side hooks from the old
# checks.nix, plus a treefmt hook that runs the treefmt config (formatter.nix).
# Provides `checks.<sys>.pre-commit` and the devshell installation script.
{inputs, ...}: {
  flake-file.inputs.pre-commit-hooks = {
    url = "github:cachix/git-hooks.nix";
    inputs.nixpkgs.follows = "nixpkgs";
  };

  imports = [inputs.pre-commit-hooks.flakeModule];

  perSystem = {config, ...}: {
    pre-commit.settings.hooks = {
      # ========== General ==========
      check-added-large-files = {
        enable = true;
        excludes = [
          "\\.png"
          "\\.jpg"
        ];
      };
      check-case-conflicts.enable = true;
      check-executables-have-shebangs.enable = true;
      check-shebang-scripts-are-executable.enable = false;
      check-merge-conflicts.enable = true;
      detect-private-keys.enable = true;
      fix-byte-order-marker.enable = true;
      mixed-line-endings.enable = true;
      trim-trailing-whitespace.enable = true;
      end-of-file-fixer.enable = true;

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
