# Dev shell via make-shell (replaces shell.nix). Installs the git hooks on
# entry; launchpad's nvim-nix gives nvim nil + alejandra inside this repo.
{inputs, ...}: {
  flake-file.inputs.make-shell.url = "github:nicknovitski/make-shell";

  imports = [inputs.make-shell.flakeModules.default];

  perSystem = {
    config,
    inputs',
    pkgs,
    ...
  }: {
    make-shells.default = {
      packages = with pkgs; [
        nix
        git
        pre-commit
        deadnix
        mdbook
        inputs'.launchpad.packages.nvim-nix
        # From the lock, not `nix run github:serokell/deploy-rs`: the nodes'
        # `activate` is built from this input and must match the CLI.
        inputs'.deploy-rs.packages.deploy-rs
      ];
      shellHook = config.pre-commit.installationScript;
    };
  };
}
