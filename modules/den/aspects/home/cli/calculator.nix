# home.calculator — qalculate, the engine rofi-calc is built on.
#
# noctalia's `noctalia-calculator` plugin was rejected: plain arithmetic over
# bundled AdvancedMath.js — no unit, currency or number-base conversion.
# libqalculate has all of those. Exposed as the `qalc` CLI (aliased `=`) and
# a floating terminal window for compositor keybinds.
{...}: {
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

    # `app-id` is what the compositor window rules match on to float it.
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
