# home.oh-my-posh — the oh-my-posh prompt as a nix-wrapper-modules package
# (`nix run .#oh-my-posh`); the wrapper bakes in the prompt config,
# home-manager only installs it and hooks it into zsh.
{inputs, ...}: let
  mkOhMyPosh = pkgs:
    inputs.nix-wrapper-modules.wrappers.oh-my-posh.wrap {
      inherit pkgs;

      settings = {
        schema = "https://raw.githubusercontent.com/JanDeDobbeleer/oh-my-posh/main/themes/schema.json";
        blocks = [
          {
            alignment = "left";
            newline = true;
            segments = [
              {
                foreground = "green";
                foreground_templates = ["{{ if .Root }}red{{end}}"];
                style = "plain";
                template = "{{ .UserName }}@{{ .HostName }} <white>in </>";
                type = "session";
              }
              {
                foreground = "blue";
                style = "plain";
                properties.style = "full";
                template = "{{ .Path }} ";
                type = "path";
              }
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
in {
  perSystem = {pkgs, ...}: {packages.oh-my-posh = mkOhMyPosh pkgs;};

  den.aspects.home."oh-my-posh".homeManager = {
    lib,
    pkgs,
    ...
  }: let
    ohMyPosh = mkOhMyPosh pkgs;
  in {
    home.packages = [ohMyPosh];

    cosmos.cli.shells.zsh.initContent = ''
      eval "$(${lib.getExe ohMyPosh} init zsh)"
    '';
  };
}
