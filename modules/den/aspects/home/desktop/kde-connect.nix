# home.kde-connect — KDE Connect user daemon plus the host firewall ports its peers connect back on.
{...}: {
  den.aspects.home.kde-connect.provides.to-hosts.nixos = {...}: {
    # Open on every interface: pairing is the access boundary.
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
    };

    # noctalia's phone-connect bar widget replaces the tray indicator.
    services.kdeconnect = {
      enable = true;
      indicator = false;
    };
  };
}
