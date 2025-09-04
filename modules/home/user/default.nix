{
  config,
  lib,
  ...
}: let
  inherit (lib.types) str nullOr;
  inherit (lib.options) mkEnableOption mkOption;
  inherit (lib.modules) mkIf mkMerge mkDefault;

  cfg = config.user;
in {
  options.user = {
    enable = mkEnableOption "user configuration";
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

  config = mkIf cfg.enable (mkMerge [
    {
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
    }
  ]);
}
