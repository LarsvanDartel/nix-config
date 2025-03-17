{
  config,
  lib,
  ...
}: let
  cfg = config.modules.shell.prompt.oh-my-posh;
in {
  options.modules.shell.prompt.oh-my-posh = {
    enable = lib.mkEnableOption "oh-my-posh shell prompt";
    theme = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      example = "star";
      description = "Preset theme to use";
    };
  };

  config = lib.mkIf cfg.enable {
    # programs.zsh.initContent = lib.mkOrder 1500 "eval \"$(${pkgs.oh-my-posh}/bin/oh-my-posh init zsh --config ${})";
    programs.oh-my-posh = {
      enable = true;
      enableBashIntegration = true;
      enableZshIntegration = true;
      useTheme = cfg.theme;
      settings = lib.mkIf (builtins.isNull cfg.theme) {
        schema = "https://raw.githubusercontent.com/JanDeDobbeleer/oh-my-posh/main/themes/schema.json";
        blocks = [
          {
            alignment = "left";
            newline = true;
            segments = [
              {
                foreground = "red";
                style = "plain";
                template = "root <white>in</> ";
                type = "root";
              }
              {
                foreground = "blue";
                style = "plain";
                properties.style = "full";
                template = "{{ .Path }} ";
                type = "path";
              }
              # {
              #   foreground = "magenta";
              #   properties.fetch_status = true;
              #   style = "plain";
              #   template = "<white>on</> {{ .HEAD }}{{if .BranchStatus }} {{ .BranchStatus }}{{ end }}{{ if .Working.Changed }}  {{ .Working.String }}{{ end }}{{ if and (.Working.Changed) (.Staging.Changed) }} |{{ end }}{{ if .Staging.Changed }}  {{ .Staging.String }}{{ end }} ";
              #   type = "git";
              # }
              # {
              #   foreground = "yellow";
              #   properties.fetch_version = true;
              #   style = "plain";
              #   template = "<white>via</>  {{ if .PackageManagerIcon }}{{ .PackageManagerIcon }} {{ end }}{{ .Full }} ";
              #   type = "node";
              # }
            ];
            type = "prompt";
          }
          {
            alignment = "left";
            newline = true;
            segments = [
              {
                foreground = "green";
                foreground_templates = ["{{ if gt .Code 0 }}red{{end}}"];
                style = "plain";
                template = ">";
                type = "text";
              }
            ];
            type = "prompt";
          }
        ];
        transient_prompt = {
          background = "transparent";
          foreground = "green";
          foreground_templates = ["{{ if gt .Code 0 }}red{{end}}"];
          template = "> ";
        };
        final_space = true;
        version = 3;
      };
    };
  };
}
