{...}: {
  flake.modules.homeManager.common = {
    config,
    lib,
    ...
  }: let
    inherit (lib.types) str nullOr;
    inherit (lib.options) mkOption;
    inherit (lib.modules) mkDefault;

    cfg = config.cosmos.user;
  in {
    options.cosmos.user = {
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

    config = {
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
  };
}
