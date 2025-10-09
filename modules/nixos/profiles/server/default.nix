{
  config,
  lib,
  ...
}: let
  inherit (lib.options) mkEnableOption;
  inherit (lib.modules) mkIf;

  cfg = config.profiles.server;
in {
  options.profiles.server = {
    enable = mkEnableOption "server configuration";
  };
  config = mkIf cfg.enable {
    profiles = {
      common.enable = true;
    };

    services = {
      getty.autologinUser = "nixos";
    };

    security.sudo = {
      wheelNeedsPassword = false;
      execWheelOnly = true;
    };

    # Notice this also disables --help for some commands such es nixos-rebuild
    documentation = {
      enable = lib.mkDefault false;
      info.enable = lib.mkDefault false;
      man.enable = lib.mkDefault false;
      nixos.enable = lib.mkDefault false;
    };

    # No need for fonts on a server
    fonts.fontconfig.enable = lib.mkDefault false;

    # UTC everywhere!
    time.timeZone = lib.mkDefault "UTC";

    # No mutable users by default
    users.mutableUsers = false;

    systemd = {
      services.NetworkManager-wait-online.enable = false;
      network.wait-online.enable = false;
      tmpfiles.rules = [
        "L+ /usr/local/bin - - - - /run/current-system/sw/bin/"
      ];

      # Given that our systems are headless, emergency mode is useless.
      # We prefer the system to attempt to continue booting so
      # that we can hopefully still access it remotely.
      enableEmergencyMode = false;

      # For more detail, see:
      #   https://0pointer.de/blog/projects/watchdog.html
      settings.Manager = {
        # systemd will send a signal to the hardware watchdog at half
        # the interval defined here, so every 10s.
        # If the hardware watchdog does not get a signal for 20s,
        # it will forcefully reboot the system.
        RuntimeWatchdogSec = "20s";
        # Forcefully reboot if the final stage of the reboot
        # hangs without progress for more than 30s.
        # For more info, see:
        #   https://utcc.utoronto.ca/~cks/space/blog/linux/SystemdShutdownWatchdog
        RebootWatchdogSec = "30s";
      };
    };

    # use TCP BBR has significantly increased throughput and reduced latency for connections
    boot.kernel.sysctl = {
      "net.core.default_qdisc" = "fq";
      "net.ipv4.tcp_congestion_control" = "bbr";
    };

    user.name = "nixos";
  };
}
