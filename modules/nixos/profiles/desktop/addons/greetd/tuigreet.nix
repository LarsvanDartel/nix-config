# tuigreet greeter for greetd. Importing it pulls in the greetd feature and
# fills in its launch command.
{config, ...}: let
  inherit (config.flake.modules.nixos) greetd;
in {
  flake.modules.nixos.tuigreet = {
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
    imports = [greetd];

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
      cosmos.system.impermanence.persist.directories = [
        "/var/cache/tuigreet"
      ];
      cosmos.profiles.desktop.addons.greetd = {
        command = mkDefault "${tuigreet} --remember --remember-user-session --greeting \"${cfg.greeting}\" --time --cmd \"${cfg.command}\" --asterisks";
      };

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
}
