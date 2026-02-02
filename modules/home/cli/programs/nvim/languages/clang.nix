{
  lib,
  config,
  pkgs,
  ...
}: let
  inherit (lib.options) mkEnableOption;
  inherit (lib.modules) mkIf;
  inherit (lib.meta) getExe';

  cfg = config.cosmos.cli.programs.nvim.languages.clang;
in {
  options.cosmos.cli.programs.nvim.languages.clang = {
    enable = mkEnableOption "clang language support nvim";
  };
  config = mkIf cfg.enable {
    programs.nixvim = {
      lsp.servers.clangd = {
        enable = true;
        config = {
          cmd = [
            "${pkgs.clang-tools}/bin/clangd"
            "--background-index"
            "--clang-tidy"
            "--header-insertion=iwyu"
            "--completion-style=detailed"
            "--function-arg-placeholders"
            "--fallback-style=llvm"
          ];
          filetypes = [
            "c"
            "cpp"
          ];
          root_markers = [
            "compile_commands.json"
            "compile_flags.txt"
            "configure.ac"
            "Makefile"
            "configure.ac"
            "configure.in"
            "config.h.in"
            "meson.build"
            "meson_options.txt"
            "build.ninja"
            ".git"
          ];
          init_options = {
            usePlaceholders = true;
            completeUnimported = true;
            clangdFileStatus = true;
          };
        };
      };

      plugins.treesitter.grammarPackages = with pkgs.vimPlugins.nvim-treesitter.builtGrammars; [
        c
        cpp
      ];

      plugins.conform-nvim.settings = {
        formatters_by_ft.cpp = ["clang_format"];
        formatters_by_ft.c = ["clang_format"];
        formatters.clang_format = {
          command = getExe' pkgs.clang-tools "clang-format";
        };
      };
    };
  };
}
