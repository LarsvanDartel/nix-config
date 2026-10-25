# nvim settings — the per-host knobs of the nvim package. One submodule, typed
# twice: `cosmos.nvim` inside the nixvim eval and HM's `cosmos.cli.programs.nvim`.
{lib, ...}: let
  inherit (lib.options) mkEnableOption mkOption;
  inherit (lib.types) bool listOf str;

  language = name: {enable = mkEnableOption "${name} language support in nvim";};
in {
  options = {
    wayland = mkEnableOption "wayland clipboard support in nvim";

    languages = {
      nix.enable = mkEnableOption "nix language support in nvim" // {default = true;};
      clang = language "clang";
      formal = language "formal";
      mcrl2 = language "mcrl2";
      python = language "python";
      rocq = language "rocq";
      rust = language "rust";
      typst = language "typst";
    };

    minuet = {
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
  };
}
