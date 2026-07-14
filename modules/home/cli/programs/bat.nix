{...}: {
  flake.modules.homeManager.common = {
    config,
    lib,
    pkgs,
    ...
  }: {
    cosmos.cli.shells.zsh.initContent = ''
      eval "$(batpipe)"
      eval "$(batman --export-env)"
    '';

    home.sessionVariables = lib.mkIf config.programs.delta.enable {
      BATDIFF_USE_DELTA = "true";
    };

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
}
