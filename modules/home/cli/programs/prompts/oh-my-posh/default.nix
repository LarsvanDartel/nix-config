{
  config,
  lib,
  ...
}: let
  inherit (lib.options) mkEnableOption mkOption;
  inherit (lib.types) nullOr str bool;
  inherit (lib.modules) mkIf;
  inherit (lib.lists) optional;

  cfg = config.cli.programs.prompt.oh-my-posh;
in {
  options.cli.programs.prompt.oh-my-posh = {
    enable = mkEnableOption "oh-my-posh shell prompt";
    theme = mkOption {
      type = nullOr str;
      default = null;
      example = "star";
      description = "Preset theme to use";
    };
    git = mkOption {
      type = bool;
      default = false;
      description = "Whether to show git status";
    };
    time = mkOption {
      type = bool;
      default = false;
      description = "Whether to show time";
    };
    session = mkOption {
      type = bool;
      default = true;
      description = "Whether to show session";
    };
  };

  config = mkIf cfg.enable {
    # programs.zsh.initContent = lib.mkOrder 1500 "eval \"$(${pkgs.oh-my-posh}/bin/oh-my-posh init zsh --config ${})";
    programs.oh-my-posh = {
      enable = true;
      enableBashIntegration = true;
      enableZshIntegration = true;
      useTheme = cfg.theme;
      settings = mkIf (cfg.theme == null) {
        schema = "https://raw.githubusercontent.com/JanDeDobbeleer/oh-my-posh/main/themes/schema.json";
        blocks =
          [
            {
              alignment = "left";
              newline = true;
              segments =
                (optional cfg.session {
                  foreground = "green";
                  foreground_templates = ["{{ if .Root }}red{{end}}"];
                  style = "plain";
                  template = "{{ .UserName }}@{{ .HostName }} <white>in </>";
                  type = "session";
                })
                ++ [
                  {
                    foreground = "blue";
                    style = "plain";
                    properties.style = "full";
                    template = "{{ .Path }} ";
                    type = "path";
                  }
                ]
                ++ (optional cfg.git
                  {
                    foreground = "magenta";
                    properties.fetch_status = true;
                    style = "plain";
                    template = "<white>on</> {{ .HEAD }}{{if .BranchStatus }} {{ .BranchStatus }}{{ end }}{{ if .Working.Changed }}  {{ .Working.String }}{{ end }}{{ if and (.Working.Changed) (.Staging.Changed) }} |{{ end }}{{ if .Staging.Changed }}  {{ .Staging.String }}{{ end }} ";
                    type = "git";
                  });
              type = "prompt";
            }
          ]
          ++ (optional cfg.time {
            alignment = "right";
            segments = [
              {
                foreground = "blue";
                style = "plain";
                properties.time_format = "15:04:05";
                template = " {{ .CurrentDate | date .Format }} ";
                type = "time";
              }
            ];
          })
          ++ [
            {
              alignment = "left";
              newline = true;
              segments = [
                {
                  foreground = "green";
                  foreground_templates = ["{{ if gt .Code 0 }}red{{end}}"];
                  style = "plain";
                  template = "{{if .Root}}#{{else}}>{{end}}";
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
          template = "{{if .Root}}#{{else}}>{{end}} ";
        };
        final_space = true;
        version = 3;
      };
    };
  };
}
