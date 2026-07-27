# desktop.greetd (+ tuigreet). greetd provides the login manager; tuigreet
# includes it and fills the launch command.
{den, ...}: {
  den.aspects.desktop.greetd.nixos = {
    config,
    lib,
    ...
  }: let
    inherit (lib.types) str;
    inherit (lib.options) mkOption;

    cfg = config.cosmos.profiles.desktop.addons.greetd;
  in {
    options.cosmos.profiles.desktop.addons.greetd.command = mkOption {
      type = str;
      default = "";
      description = "Command to run to show greeter";
    };

    config.services.greetd = {
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

  den.aspects.desktop.tuigreet = {
    includes = [den.aspects.desktop.greetd];
    nixos = {
      config,
      lib,
      pkgs,
      ...
    }: let
      inherit (lib.types) str;
      inherit (lib.options) mkOption;
      inherit (lib.modules) mkDefault;

      cfg = config.cosmos.profiles.desktop.addons.greetd.tuigreet;
      tuigreet = "${pkgs.tuigreet}/bin/tuigreet";
    in {
      options.cosmos.profiles.desktop.addons.greetd.tuigreet = {
        greeting = mkOption {
          type = str;
          default = "Welcome to ${config.networking.hostName}";
          description = "Greeting message to show";
        };
        command = mkOption {
          type = str;
          default = "";
          description = "Command to run after login";
        };
      };

      config = {
        cosmos.system.impermanence.persist.directories = ["/var/cache/tuigreet"];
        cosmos.profiles.desktop.addons.greetd.command =
          mkDefault ''${tuigreet} --remember --remember-user-session --greeting "${cfg.greeting}" --time --cmd "${cfg.command}" --asterisks'';

        systemd.services.greetd.serviceConfig = {
          Type = "idle";
          StandardInput = "tty";
          StandardOutput = "tty";
          StandardError = "journal";
          TTYReset = true;
          TTYVHangup = true;
          TTYVTDisallocate = true;
        };
      };
    };
  };
}
