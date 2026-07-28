# home.which-key — tmux which-key plugin (extends the tmux config).
{...}: {
  den.aspects.home.which-key.homeManager = {
    config,
    lib,
    pkgs,
    ...
  }: let
    inherit (lib.options) mkOption mkPackageOption;

    cfg = config.cosmos.cli.programs.tmux.plugins.which-key;
    rtpPath = "tmux/plugins/tmux-which-key";
  in {
    options.cosmos.cli.programs.tmux.plugins.which-key = {
      package = mkPackageOption pkgs ["tmuxPlugins" "tmux-which-key"] {};
      settings = mkOption {
        type = with lib.types; let
          valueType =
            nullOr (oneOf [
              bool
              int
              float
              str
              path
              (attrsOf valueType)
              (listOf valueType)
            ])
            // {
              description = "tmux-which-key configuration value";
            };
        in
          valueType;
        default = let
          fromYaml = file: let
            convertedJson =
              pkgs.runCommand "config.json"
              {
                nativeBuildInputs = [pkgs.yj];
              }
              ''
                ${lib.getExe pkgs.yj} < ${file} > $out
              '';
          in
            builtins.fromJSON (builtins.readFile "${convertedJson}");
        in
          fromYaml "${cfg.package}/share/tmux-plugins/tmux-which-key/config.example.yaml";
      };
    };

    config = let
      configYaml = lib.generators.toYAML {} cfg.settings;
      configTmux =
        pkgs.runCommand "init.tmux"
        {
          nativeBuildInputs = cfg.package.buildInputs;
        }
        ''
          set -x
          echo '${configYaml}' > config.yaml
          ${lib.getExe pkgs.python3} "${cfg.package}/share/tmux-plugins/tmux-which-key/plugin/build.py" \
            config.yaml $out
        '';
    in {
      xdg.dataFile."${rtpPath}/init.tmux".source = configTmux;
      programs.tmux.plugins = [
        {
          plugin = cfg.package;
          extraConfig = ''
            set -g @tmux-which-key-xdg-enable 1;
            set -g @tmux-which-key-disable-autobuild 1
            set -g @tmux-which-key-xdg-plugin-path "${rtpPath}"
          '';
        }
      ];
    };
  };
}
