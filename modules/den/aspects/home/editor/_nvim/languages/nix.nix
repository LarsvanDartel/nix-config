# nvim nix — nil, the nix grammar and alejandra.
{
  lib,
  config,
  pkgs,
  ...
}: let
  inherit (lib.modules) mkIf;
  inherit (lib.meta) getExe;

  cfg = config.cosmos.nvim.languages.nix;
in {
  config = mkIf cfg.enable {
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
