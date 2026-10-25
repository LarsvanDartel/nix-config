# minuet — LLM completion against the fleet's own ollama (endeavour only).
# Opt-in per host (settings.nix): elsewhere completions silently time out.
# FIM, not chat: only /v1/completions takes a suffix.
{
  lib,
  config,
  ...
}: let
  cfg = config.cosmos.nvim.minuet;
in {
  config = lib.mkIf cfg.enable {
    plugins.minuet = {
      enable = true;

      settings = {
        provider = "openai_fim_compatible";

        n_completions = 1;

        # Prompt processing is this GPU's bottleneck; context size decides latency.
        context_window = 512;

        provider_options.openai_fim_compatible = {
          name = "ollama";
          end_point = cfg.endpoint;
          inherit (cfg) model;

          # An env-var *name*; ollama needs no key, so any always-set var.
          api_key = "TERM";

          optional = {
            max_tokens = 128;
            top_p = 0.9;
          };
        };

        virtualtext = {
          auto_trigger_ft = lib.optionals cfg.autoTrigger cfg.filetypes;

          keymap = {
            accept = "<A-y>";
            accept_line = "<A-l>";
            prev = "<A-[>";
            next = "<A-]>";
            dismiss = "<A-e>";
          };
        };
      };
    };

    keymaps = [
      {
        mode = "i";
        key = "<A-i>";
        action.__raw = "function() require('minuet.virtualtext').action.next() end";
        options = {
          silent = true;
          desc = "minuet: suggest completion";
        };
      }
    ];
  };
}
