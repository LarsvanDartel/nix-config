{
  config,
  lib,
  ...
}: let
  cfg = config.modules.greetd;
in {
  imports = [
    ./tuigreet.nix
  ];

  options.modules.greetd = {
    enable = lib.mkEnableOption "greetd";
    command = lib.mkOption {
      type = lib.types.str;
      default = "";
      description = "Command to run to show greeter";
    };
  };

  config = lib.mkIf cfg.enable {
    services.greetd = {
      enable = true;
      settings.default_session = {
        command = cfg.command;
        user = lib.mkDefault "greeter";
      };
    };
  };
}
