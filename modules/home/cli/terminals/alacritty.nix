# Alacritty, built with nix-wrapper-modules (BirdeeHub) rather than
# home-manager's programs.alacritty. The wrapper bakes `settings` into a
# portable derivation.
#
# NOTE: a wrapped program reads its baked config, so it does NOT receive stylix
# theming (which works through home-manager's programs.*/stylix targets). This
# is why the stylix-themed terminals/programs in this config stay on
# home-manager; alacritty (unused by default here) is the wrapper-modules pilot.
{
  inputs,
  config,
  ...
}: let
  inherit (config.flake.modules.homeManager) terminals;
in {
  flake-file.inputs.nix-wrapper-modules.url = "github:BirdeeHub/nix-wrapper-modules";

  flake.modules.homeManager.alacritty = {pkgs, ...}: let
    alacritty = inputs.nix-wrapper-modules.wrappers.alacritty.wrap {
      inherit pkgs;
      settings.terminal.shell.program = "${pkgs.zsh}/bin/zsh";
      settings.terminal.shell.args = ["-l"];
    };
  in {
    imports = [terminals];

    cosmos.cli.terminals.default = "${alacritty}/bin/alacritty";

    home.packages = [alacritty];
  };
}
