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
      # No overrideAttrs: the old patch rewrote expand('<sfile>:p:h:h') in
      # autoload/coqtail.vim, but that call only exists in plugin/coqtail.vim
      # — it never matched and the derivation was unchanged. If the symlink
      # issue is ever real, patch plugin/coqtail.vim with --replace-fail so
      # an upstream move breaks the build instead of silently reverting.
      extraPlugins = [pkgs.vimPlugins.Coqtail];
    };
  };
}
