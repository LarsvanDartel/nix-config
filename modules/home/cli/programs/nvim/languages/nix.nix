{
  lib,
  pkgs,
  ...
}: let
  inherit (lib.meta) getExe;
in {
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
}
