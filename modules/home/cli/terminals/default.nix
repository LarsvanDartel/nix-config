{
  config,
  lib,
  ...
}: let
  inherit (lib.types) str;
  inherit (lib.options) mkOption;

  cfg = config.cli.terminal;
in {
  options.cli.terminals = {
    default = mkOption {
      type = str;
      default = "foot";
      description = "Default terminal application";
    };
    defaultStandalone = mkOption {
      type = str;
      inherit (cfg) default;
      description = "Default standalone terminal application (without server mode)";
    };
  };
}
