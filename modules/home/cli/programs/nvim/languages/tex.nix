{
  config,
  lib,
  pkgs,
  ...
}: let
  inherit (lib.options) mkEnableOption;
  inherit (lib.modules) mkIf;

  cfg = config.cli.programs.nvim.languages.tex;
in {
  # TODO: Remove when https://github.com/NotAShelf/nvf/pull/569 is merged
  options.cli.programs.nvim.languages.tex = {
    enable = mkEnableOption "tex";
  };

  config = mkIf cfg.enable {
    system.impermanence.persist.directories = [".cache/Tectonic"];
    programs.nvf.settings.vim = {
      treesitter = {
        enable = true;
        grammars = with pkgs.vimPlugins.nvim-treesitter.builtGrammars; [
          bibtex
          latex
        ];
      };
      lsp = {
        lspconfig = {
          enable = true;
          sources = {
            texlab = ''
              lspconfig.texlab.setup {
                settings = {
                  texlab = {
                    completion = {
                      matcher = "fuzzy-ignore-case";
                    };
                    diagnosticsDelay = 100;
                    formatterLineLength = 80;
                    bibtexFormatter = "texlab";
                    latexFormatter = "latexindent";
                    latexindent = {
                      modifyLineBreaks = true;
                    };
                    inlayHints = {
                      labelDefinitions = true;
                      labelReferences = true;
                    };
                    build = {
                      onSave = true;
                      forwardSearchAfter = true;
                      args = { "-X", "compile", "%f", "--keep-logs", "-Z", "shell-escape-cwd=." };
                      executable = "${pkgs.tectonic}/bin/tectonic";
                    };
                    forwardSearch = {
                      args = { "--synctex-forward", "%l:1:%f", "%p" };
                      executable = "${pkgs.zathura}/bin/zathura";
                    };
                  };
                };
                cmd = { "${pkgs.texlab}/bin/texlab" };
              }
            '';
          };
        };
      };
      extraPackages = [pkgs.texlivePackages.chktex];
    };
  };
}
