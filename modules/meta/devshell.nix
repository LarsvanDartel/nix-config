# Dev shell via make-shell (replaces shell.nix). Installs the git hooks on entry.
{inputs, ...}: {
  flake-file.inputs.make-shell.url = "github:nicknovitski/make-shell";

  imports = [inputs.make-shell.flakeModules.default];

  perSystem = {
    config,
    pkgs,
    ...
  }: {
    make-shells.default = {
      packages = with pkgs; [
        nix
        git
        pre-commit
        deadnix
      ];
      shellHook = config.pre-commit.installationScript;
    };
  };
}
