{
  lib,
  config,
  pkgs,
  ...
}: let
  inherit (lib.options) mkEnableOption;
  inherit (lib.modules) mkIf;
  inherit (lib.meta) getExe;

  cfg = config.cosmos.cli.programs.nvim.languages.nix;
in {
  options.cosmos.cli.programs.nvim.languages.nix = {
    enable = mkEnableOption "nix language support nvim" // {default = true;};
  };
  config = mkIf cfg.enable {
    programs.nixvim = {
      lsp.servers.nil = {
        enable = true;
        config = {
          cmd = [
            "${getExe pkgs.nil}"
          ];
          filetypes = [
            "nix"
          ];
          root_markers = [
            "flake.nix"
            ".git"
          ];
        };
      };

      plugins.treesitter.grammarPackages = with pkgs.vimPlugins.nvim-treesitter.builtGrammars; [
        nix
      ];

      plugins.conform-nvim.settings = {
        formatters_by_ft.nix = ["alejandra"];
        formatters.alejandra = {
          command = getExe pkgs.alejandra;
        };
      };
    };
  };
}
