{
  config,
  lib,
  ...
}: let
  inherit (lib.types) str nullOr;
  inherit (lib.options) mkEnableOption mkOption;
  inherit (lib.modules) mkIf mkDefault;

  cfg = config.cosmos.user;
in {
  options.cosmos.user = {
    enable = mkEnableOption "user configuration" // {default = true;};
    name = mkOption {
      type = nullOr str;
      default = null;
      description = "The name of the user";
    };
    home = mkOption {
      type = str;
      default = "/home/${cfg.name}";
      description = "The home directory of the user";
    };
  };

  config = mkIf cfg.enable {
    assertions = [
      {
        assertion = cfg.name != null;
        message = "user.name must be set";
      }
    ];

    home = {
      homeDirectory = mkDefault cfg.home;
      username = mkDefault cfg.name;
    };
  };
}
