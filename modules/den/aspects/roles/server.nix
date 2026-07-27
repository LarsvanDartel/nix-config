# roles.server — headless baseline (was flake.modules.nixos.server in
# modules/nixos/profiles/server.nix). Included by server hosts.
{...}: {
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
