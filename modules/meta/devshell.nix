# devshell — the default dev shell (make-shell); installs the git hooks on entry.
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
      ];
      shellHook = config.pre-commit.installationScript;
    };
  };
}
