# bat. The portable `programs.bat` config lives in its own named module so it can
# be wrapped as a standalone package (modules/meta/hm-wrappers.nix); the
# cross-cutting shell glue (batpipe/batman init, delta integration) stays in the
# `common` aggregate, which imports the named module.
{config, ...}: let
  inherit (config.flake.modules.homeManager) bat;
in {
  flake.modules.homeManager.bat = {pkgs, ...}: {
    programs.bat = {
      enable = true;

      extraPackages = with pkgs.bat-extras; [
        batgrep
        batman
        batpipe
        batwatch
        batdiff
      ];
    };
  };

  flake.modules.homeManager.common = {
    config,
    lib,
    ...
  }: {
    imports = [bat];

    cosmos.cli.shells.zsh.initContent = ''
      eval "$(batpipe)"
      eval "$(batman --export-env)"
    '';

    home.sessionVariables = lib.mkIf config.programs.delta.enable {
      BATDIFF_USE_DELTA = "true";
    };
  };
}
