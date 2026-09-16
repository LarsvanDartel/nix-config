# roles.server — headless baseline. Included by server hosts.
{den, ...}: {
  # Server-only, deliberately not in roles.default: nobody sits at a server,
  # while a laptop's failures are mostly yours and suspend/resume churn
  # would make the notifications noise.
  den.aspects.roles.server.includes = [
    den.aspects.core.notify-failure
    # Says so when a deploy has staged a new kernel that is not running yet.
    # Notifies rather than reboots — see the aspect for why.
    den.aspects.core.reboot-required
    # Host metrics on every server, scraped from endeavour over the mesh.
    den.aspects.services.node-exporter
  ];

  den.aspects.roles.server.nixos = {lib, ...}: {
    cosmos.user.name = "nixos";

    services.getty.autologinUser = "nixos";

    security.sudo = {
      wheelNeedsPassword = false;
      execWheelOnly = true;
    };

    documentation = {
      enable = lib.mkDefault false;
      info.enable = lib.mkDefault false;
      man.enable = lib.mkDefault false;
      nixos.enable = lib.mkDefault false;
    };

    fonts.fontconfig.enable = lib.mkDefault false;

    time.timeZone = lib.mkDefault "UTC";

    users.mutableUsers = false;

    systemd = {
      services.NetworkManager-wait-online.enable = false;
      network.wait-online.enable = false;
      tmpfiles.rules = [
        "L+ /usr/local/bin - - - - /run/current-system/sw/bin/"
      ];
      enableEmergencyMode = false;
      settings.Manager = {
        RuntimeWatchdogSec = "20s";
        RebootWatchdogSec = "30s";
      };
    };

    boot.kernel.sysctl = {
      "net.core.default_qdisc" = "fq";
      "net.ipv4.tcp_congestion_control" = "bbr";
    };
  };
}
