# home.bat (+ its shell glue: batpipe/batman init, delta integration).
{...}: {
  den.aspects.home.bat.homeManager = {
    config,
    lib,
    pkgs,
    ...
  }: {
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

    cosmos.cli.shells.zsh.initContent = ''
      eval "$(batpipe)"
      eval "$(batman --export-env)"
    '';

    home.sessionVariables = lib.mkIf config.programs.delta.enable {
      BATDIFF_USE_DELTA = "true";
    };
  };
}
