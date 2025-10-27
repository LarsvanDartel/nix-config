{
  config,
  lib,
  pkgs,
  ...
}: let
  inherit (lib.types) str;
  inherit (lib.options) mkOption mkEnableOption;
  inherit (lib.modules) mkIf mkDefault;

  cfg = config.cosmos.profiles.desktop.addons.greetd.tuigreet;
  tuigreet = "${pkgs.tuigreet}/bin/tuigreet";
in {
  options.cosmos.profiles.desktop.addons.greetd.tuigreet = {
    enable = mkEnableOption "tuigreet";
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

  config = mkIf cfg.enable {
    cosmos.system.impermanence.persist.directories = [
      "/var/cache/tuigreet"
    ];
    cosmos.profiles.desktop.addons.greetd = {
      enable = mkDefault true;
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
}
