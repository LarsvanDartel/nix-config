{...}: {
  flake.modules.homeManager.terminals = {
    config,
    lib,
    ...
  }: let
    inherit (lib.types) str;
    inherit (lib.options) mkOption;
  in {
    options.cosmos.cli.terminals = {
      default = mkOption {
        type = str;
        default = "foot";
        description = "Default terminal application";
      };
      defaultStandalone = mkOption {
        type = str;
        default = config.cosmos.cli.terminals.default;
        description = "Default standalone terminal application (without server mode)";
      };
    };
  };
}
