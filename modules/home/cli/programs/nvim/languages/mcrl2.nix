{
  config,
  lib,
  pkgs,
  ...
}: let
  inherit (lib.options) mkEnableOption;
  inherit (lib.modules) mkIf;

  cfg = config.cosmos.cli.programs.nvim.languages.mcrl2;
in {
  options.cosmos.cli.programs.nvim.languages.mcrl2 = {
    enable = mkEnableOption "mcrl2";
  };
  config = mkIf cfg.enable {
    programs.nvf.settings.vim = {
      extraPlugins.mcrl2-syntax = {
        package = pkgs.vimUtils.buildVimPlugin {
          name = "mcrl2-syntax";
          src = pkgs.fetchFromGitHub {
            owner = "mCRL2org";
            repo = "mCRL2";
            rev = "772beafbcdecd0b692fa5be9f4a57caa2f8d5169";
            sha256 = "sha256-v90IurwELQuqfQwh8wMuUvN3Jo2CnianEcgwjunH4uM=";
          };
          postInstall = ''
            mkdir -p $out
            cp -r $src/.vim/* $out/
          '';
        };
      };
    };
  };
}
