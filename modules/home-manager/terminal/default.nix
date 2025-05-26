{
  config,
  lib,
  ...
}: let
  cfg = config.modules.terminal;
in {
  imports = [
    ./emulator
    ./programs
    ./shell
  ];

  options.modules.terminal = {
    default = lib.mkOption {
      type = lib.types.str;
      default = "foot";
      description = "Default terminal application";
    };
    defaultStandalone = lib.mkOption {
      type = lib.types.str;
      inherit (cfg) default;
      description = "Default standalone terminal application (without server mode)";
    };
  };
}
