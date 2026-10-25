# home.which-key — tmux which-key plugin, layered onto this host's tmux wrapper.
{...}: {
  den.aspects.home.which-key.homeManager = {
    config,
    lib,
    pkgs,
    ...
  }: let
    inherit (lib.options) mkOption mkPackageOption;

    cfg = config.cosmos.cli.programs.tmux.plugins.which-key;
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
      # plugin.sh.tmux only copies the prebuilt init.tmux into $XDG_DATA_HOME
      # and sources it from there; sourcing the store copy needs no file in $HOME.
      cosmos.cli.programs.tmux.wrapperModule.configBefore = ''
        source-file ${configTmux}
      '';
    };
  };
}
