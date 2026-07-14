{...}: {
  flake.modules.nixos.greetd = {
    config,
    lib,
    ...
  }: let
    inherit (lib.types) str;
    inherit (lib.options) mkOption;

    cfg = config.cosmos.profiles.desktop.addons.greetd;
  in {
    options.cosmos.profiles.desktop.addons.greetd = {
      command = mkOption {
        type = str;
        default = "";
        description = "Command to run to show greeter";
      };
    };

    config = {
      services.greetd = {
        enable = true;
        settings = rec {
          default_session = {
            inherit (cfg) command;
            user = config.cosmos.user.name;
          };
          initial_session = default_session;
        };
      };
    };
  };
}
