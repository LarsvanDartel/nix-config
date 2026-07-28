# home.calculator — qalculate, the engine rofi-calc is built on.
#
# noctalia's official `noctalia-calculator` plugin was considered and rejected:
# it is plain arithmetic over a bundled AdvancedMath.js (button grid, operator
# precedence) with no unit, currency or number-base conversion. rofi-calc gets
# those from libqalculate, so we use libqalculate directly.
#
# `qalc` handles everything asked for:
#   3 ft + 2 m to cm       · unit conversion
#   100 EUR to USD         · currency (exchange rates fetched and cached)
#   0xff + 0b1011 to hex   · base conversion
#   sqrt(2)^3, 15% of 80   · the usual maths
#
# Exposed two ways: the `qalc` CLI (also aliased as `=`), and a floating
# terminal window that compositors bind to a key — the closest thing to
# rofi-calc's pop-up feel.
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

    # `app-id` is what the compositor window rules match on to float it.
    launcher =
      pkgs.writeShellScriptBin "calculator"
      ''exec ${terminal} --app-id=calculator -- ${lib.getExe' pkgs.libqalculate "qalc"} "$@"'';
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
        pkgs.libqalculate # qalc
        pkgs.qalculate-gtk # full GUI, for when a window beats a prompt
        launcher
      ];

      # NOT `=`: zsh reserves a leading `=` for EQUALS expansion, so it cannot be
      # a command name. home-manager emits `alias -- '='=qalc`, which zsh rejects
      # at startup with "bad assignment"; escaping the name or `unsetopt equals`
      # doesn't help either — the alias is simply never resolved.
      cosmos.cli.shells.zsh.aliases.calc = "qalc";

      cosmos.system.impermanence.persist.directories = [".config/qalculate"];
    };
  };
}
