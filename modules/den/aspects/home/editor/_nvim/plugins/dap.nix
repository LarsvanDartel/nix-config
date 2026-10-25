# nvim dap — nvim-dap, dap-ui and virtual text on <leader>d and the F-keys;
# codelldb for rust/C/C++ and debugpy for python, each gated on its language.
{
  lib,
  config,
  pkgs,
  ...
}: let
  inherit (lib.modules) mkIf;

  langs = config.cosmos.nvim.languages;
  codelldb = {
    enable = langs.rust.enable || langs.clang.enable;
    # The adapter's bin/codelldb wrapper points lldb at its lldb-server.
    command = lib.getExe' pkgs.vscode-extensions.vadimcn.vscode-lldb.adapter "codelldb";
  };

  codelldbLaunch = {
    type = "codelldb";
    request = "launch";
    name = "Launch executable";
    program.__raw = ''
      function()
        return vim.fn.input("Path to executable: ", vim.fn.getcwd() .. "/", "file")
      end
    '';
    cwd = "\${workspaceFolder}";
    stopOnEntry = false;
  };

  dap = fn: {__raw = "function() require('dap').${fn} end";};
in {
  config = mkIf (codelldb.enable || langs.python.enable) {
    plugins = {
      dap = {
        enable = true;

        adapters.servers = mkIf codelldb.enable {
          codelldb = {
            port = "\${port}";
            executable = {
              inherit (codelldb) command;
              args = ["--port" "\${port}"];
            };
          };
        };

        configurations = mkIf langs.clang.enable {
          c = [codelldbLaunch];
          cpp = [codelldbLaunch];
        };

        signs = {
          dapBreakpoint = {
            text = "●";
            texthl = "DiagnosticError";
          };
          dapBreakpointCondition = {
            text = "◆";
            texthl = "DiagnosticWarn";
          };
          dapLogPoint = {
            text = "◉";
            texthl = "DiagnosticInfo";
          };
          dapStopped = {
            text = "→";
            texthl = "DiagnosticOk";
            linehl = "Visual";
          };
          dapBreakpointRejected = {
            text = "○";
            texthl = "DiagnosticError";
          };
        };
      };

      dap-ui = {
        enable = true;
        luaConfig.post = ''
          do
            local dap, dapui = require("dap"), require("dapui")
            local open, close = function() dapui.open() end, function() dapui.close() end
            dap.listeners.before.attach.dapui = open
            dap.listeners.before.launch.dapui = open
            dap.listeners.before.event_terminated.dapui = close
            dap.listeners.before.event_exited.dapui = close
          end
        '';
      };

      dap-virtual-text.enable = true;

      dap-python.enable = langs.python.enable;

      rustaceanvim.settings.dap.adapter = mkIf langs.rust.enable {
        type = "server";
        host = "127.0.0.1";
        port = "\${port}";
        executable = {
          inherit (codelldb) command;
          args = ["--port" "\${port}"];
        };
      };
    };

    keymaps = let
      n = key: action: desc: {
        mode = "n";
        inherit key action;
        options.desc = desc;
      };
    in [
      (n "<leader>db" (dap "toggle_breakpoint()") "Toggle breakpoint")
      (n "<leader>dB" (dap "set_breakpoint(vim.fn.input('Breakpoint condition: '))") "Conditional breakpoint")
      (n "<leader>dc" (dap "continue()") "Continue/start")
      (n "<leader>di" (dap "step_into()") "Step into")
      (n "<leader>do" (dap "step_over()") "Step over")
      (n "<leader>dO" (dap "step_out()") "Step out")
      (n "<leader>dl" (dap "run_last()") "Run last")
      (n "<leader>dt" (dap "terminate()") "Terminate")
      (n "<leader>du" {__raw = "function() require('dapui').toggle() end";} "Toggle dap-ui")
      (n "<leader>dr" (dap "repl.toggle()") "Toggle REPL")
      {
        mode = ["n" "x"];
        key = "<leader>de";
        action.__raw = "function() require('dapui').eval() end";
        options.desc = "Evaluate expression";
      }
      (n "<F5>" (dap "continue()") "Debug: continue/start")
      (n "<F9>" (dap "toggle_breakpoint()") "Debug: toggle breakpoint")
      (n "<F10>" (dap "step_over()") "Debug: step over")
      (n "<F11>" (dap "step_into()") "Debug: step into")
      (n "<S-F11>" (dap "step_out()") "Debug: step out")
    ];
  };
}
