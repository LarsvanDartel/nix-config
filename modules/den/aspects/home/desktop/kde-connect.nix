# home.kde-connect — split across nixos and homeManager: the daemon is a user
# service, but the peer answers discovery by initiating a TCP connection back
# to this machine, which needs a hole in the host firewall (NixOS level).
{...}: {
  den.aspects.home.kde-connect.nixos = {...}: {
    # Full range, TCP and UDP: devices claim the first free port and discovery
    # needs both protocols. Open on every interface; pairing is the boundary.
    networking.firewall = {
      allowedTCPPortRanges = [
        {
          from = 1714;
          to = 1764;
        }
      ];
      allowedUDPPortRanges = [
        {
          from = 1714;
          to = 1764;
        }
      ];
    };
  };

  den.aspects.home.kde-connect.homeManager = {...}: {
    cosmos.system.impermanence.persist.directories = [".config/kdeconnect"];

    xdg.desktopEntries = {
      "org.kde.kdeconnect.sms" = {
        exec = "";
        name = "KDE Connect SMS";
        settings.NoDisplay = "true";
      };
      "org.kde.kdeconnect.nonplasma" = {
        exec = "";
        name = "KDE Connect Indicator";
        settings.NoDisplay = "true";
      };
      "org.kde.kdeconnect.app" = {
        exec = "";
        name = "KDE Connect";
        settings.NoDisplay = "true";
      };
    };

    services.kdeconnect = {
      enable = true;
      indicator = true;
    };
  };
}
