# home.bat — bat with bat-extras and its shell glue
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
