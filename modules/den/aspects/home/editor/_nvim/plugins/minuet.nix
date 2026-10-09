# minuet — LLM completion against the fleet's own ollama (endeavour only).
# Opt-in per host: elsewhere completions silently time out. FIM, not chat:
# only /v1/completions takes a suffix.
{
  lib,
  config,
  ...
}: let
  inherit (lib.options) mkEnableOption mkOption;
  inherit (lib.modules) mkIf;
  inherit (lib.types) bool listOf str;

  cfg = config.cosmos.cli.programs.nvim.minuet;
in {
  options.cosmos.cli.programs.nvim.minuet = {
    enable = mkEnableOption "LLM completion via minuet against the local ollama";

    endpoint = mkOption {
      type = str;
      default = "http://endeavour.nb.lvdar.nl:11434/v1/completions";
      description = ''
        ollama's OpenAI-compatible completions endpoint. A cross-host literal,
        like every other address in this repo — den cannot read endeavour's
        config, so this must track cosmos.services.ollama there.

        `/v1/completions`, not `/v1/chat/completions`: fill-in-middle lives on
        the legacy completions route because it is the one that takes a
        `suffix` alongside the prompt.
      '';
    };

    model = mkOption {
      type = str;
      default = "qwen2.5-coder:3b";
      description = ''
        Small on purpose. The 14B sibling is a far better writer and generates
        at 12.5 tok/s, which is an order of magnitude too slow to appear
        between keystrokes — completion is a latency problem before it is a
        quality one. ~2 G also means it coexists with a resident 14B in the
        card's 16 G rather than evicting it on every keypress.
      '';
    };

    autoTrigger = mkOption {
      type = bool;
      default = false;
      description = ''
        Fire on every pause in insert mode rather than on demand.

        Off by default for two reasons. It sends a request per pause to a GPU
        shared with everything else on endeavour, and — more practically —
        voyager is a laptop that roams, so off the mesh every automatic
        trigger becomes a timeout. With manual invocation a failed request is
        a keypress that did nothing, which is a much better failure.
      '';
    };

    filetypes = mkOption {
      type = listOf str;
      default = ["nix" "rust" "python" "lua" "sh" "typst"];
      description = "Filetypes to auto-trigger in, when autoTrigger is on.";
    };
  };

  config = mkIf cfg.enable {
    programs.nixvim.plugins.minuet = {
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

    programs.nixvim.keymaps = [
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
