# home.kde-connect — split across nixos and homeManager: the daemon is a user
# service, but the peer answers discovery by initiating a TCP connection back
# to this machine, which needs a hole in the host firewall (NixOS level).
{...}: {
  den.aspects.home.kde-connect.nixos = {...}: {
    # Full 1714-1764 range, TCP and UDP: a device claims the first free port
    # in the range and advertises it in its identity packet, so pinning 1716
    # fails invisibly once something else took it; discovery is UDP broadcast
    # answered by a TCP connection back, so one protocol alone leaves the
    # handshake half-finished. Open on every interface, like the catt and
    # Minecraft ports in voyager.nix: the untrusted network rides the same
    # interface as the trusted one, and pairing is the real boundary — an
    # unpaired peer only gets a pairing request to accept, not access.
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
