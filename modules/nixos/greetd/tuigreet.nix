{
  config,
  lib,
  pkgs,
  ...
}: let
  cfg = config.modules.tuigreet;
  tuigreet = "${pkgs.greetd.tuigreet}/bin/tuigreet";
in {
  options.modules.tuigreet = {
    enable = lib.mkEnableOption "tuigreet";
    greeting = lib.mkOption {
      type = lib.types.str;
      default = "Welcome to ${config.networking.hostName}";
      description = "Greeting message to show";
    };
    command = lib.mkOption {
      type = lib.types.str;
      default = "";
      description = "Command to run after login";
    };
  };

  config = lib.mkIf cfg.enable {
    modules.persist.directories = [
      "/var/cache/tuigreet"
    ];
    modules.greetd = {
      enable = lib.mkDefault true;
      command = lib.mkDefault "${tuigreet} --remember --remember-user-session --greeting \"${cfg.greeting}\" --time --cmd \"${cfg.command}\" --asterisks";
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
