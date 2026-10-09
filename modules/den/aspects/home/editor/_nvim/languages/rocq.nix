{
  lib,
  config,
  pkgs,
  ...
}: let
  inherit (lib.options) mkEnableOption;
  inherit (lib.modules) mkIf;

  cfg = config.cosmos.cli.programs.nvim.languages.rocq;
in {
  options.cosmos.cli.programs.nvim.languages.rocq = {
    enable = mkEnableOption "rocq language support nvim";
  };
  config = mkIf cfg.enable {
    programs.nixvim = {
      withPython3 = true;

      extraPackages = with pkgs; [
        (python3.withPackages (ps:
          with ps; [
            pynvim
          ]))
      ];
      # If a symlink issue appears, patch plugin/coqtail.vim (not autoload/)
      # with --replace-fail so an upstream move breaks the build.
      extraPlugins = [pkgs.vimPlugins.Coqtail];
    };
  };
}
