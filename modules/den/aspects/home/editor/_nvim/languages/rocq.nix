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
      # Plain, unpatched. There used to be an overrideAttrs here rewriting
      # `expand('<sfile>:p:h:h')` in autoload/coqtail.vim so the plugin found
      # its python/ directory through a symlink. It did nothing: the only such
      # call lives in plugin/coqtail.vim, and nixpkgs said so on every build —
      # "pattern ... doesn't match anything in file 'autoload/coqtail.vim'".
      # The patched derivation was byte-identical to the unpatched one.
      #
      # If the symlink problem ever shows up for real, patch plugin/coqtail.vim
      # and use --replace-fail, so the next upstream move breaks the build
      # instead of quietly reverting the fix.
      extraPlugins = [pkgs.vimPlugins.Coqtail];
    };
  };
}
