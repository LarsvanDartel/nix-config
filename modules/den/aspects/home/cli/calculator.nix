# home.calculator — qalc in a terminal window, the engine rofi-calc is built on
{...}: {
  # Not noctalia's calculator plugin: it lacks unit, currency and number-base conversion.
  den.aspects.home.calculator.homeManager = {
    config,
    lib,
    pkgs,
    ...
  }: let
    inherit (lib.options) mkOption;
    inherit (lib.types) str;

    terminal = config.cosmos.cli.terminals.defaultStandalone;

    qalc =
      pkgs.writeShellScriptBin "qalc"
      ''exec ${lib.getExe' pkgs.libqalculate "qalc"} -set "autocalc 1" "$@"'';

    launcher =
      pkgs.writeShellScriptBin "calculator"
      ''exec ${terminal} --app-id=calculator -- ${lib.getExe qalc} "$@"'';
  in {
    options.cosmos.cli.programs.calculator.command = mkOption {
      type = str;
      readOnly = true;
      default = lib.getExe launcher;
      description = ''
        Command that opens the calculator in a floating terminal, for compositor
        keybinds. The window's app-id is "calculator".
      '';
    };

    config = {
      home.packages = [
        qalc
        pkgs.qalculate-gtk
        launcher
      ];

      cosmos.system.impermanence.persist.directories = [".config/qalculate"];
    };
  };
}
