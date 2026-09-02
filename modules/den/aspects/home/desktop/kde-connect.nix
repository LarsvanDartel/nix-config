# home.kde-connect
#
# Split across nixos and homeManager: the daemon is a user service, but
# discovery is not something a user service can arrange for itself. The
# protocol pairs a UDP broadcast with a TCP connection back the other way, so
# the peer always ends up *initiating* to this machine — which needs a hole in
# the host firewall, and that only exists at the NixOS level.
{...}: {
  den.aspects.home.kde-connect.nixos = {...}: {
    # KDE Connect's whole range, TCP and UDP, not just :1716. A device claims
    # the first free port in 1714-1764 and advertises it in the identity
    # packet, so the one actually in use is only 1716 as long as nothing else
    # on the machine got there first. Pinning 1716 works right up until it
    # doesn't, and the failure looks exactly like this one: a daemon running,
    # listening, and invisible.
    #
    # Both protocols because discovery uses both in opposite directions. Each
    # side broadcasts an identity packet over UDP, and the receiver answers by
    # opening a TCP connection back to the advertised port — so a rule for one
    # protocol alone leaves the handshake half-finished. That is also why the
    # symptom is mutual: neither device can see the other, no matter which one
    # you press "refresh" on.
    #
    # Open on every interface, as with the catt and Minecraft ports in
    # voyager.nix, and for the same reason: on a laptop the untrusted network
    # arrives on the same interface as the trusted one, so scoping to the
    # wireless device buys nothing. Pairing is the real boundary here — an
    # unpaired peer that reaches the port gets a pairing request the user has
    # to accept, not access.
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
