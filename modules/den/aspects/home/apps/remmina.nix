# home.remmina — Remmina RDP client with the GEWISMGMT profile.
{den, ...}: {
  den.aspects.home.remmina = {
    # Saved passwords go to the Secret Service, not the profile.
    includes = [den.aspects.home.keyring];

    homeManager = {lib, ...}: {
      services.remmina = {
        enable = true;
        systemdService.enable = false;
      };

      # data/RDP holds FreeRDP's trusted certificate fingerprints.
      cosmos.system.impermanence.persist.directories = [
        ".config/remmina"
        ".local/share/remmina"
      ];

      # Remmina rewrites a profile on every connect, replacing the symlink;
      # force puts it back on the next activation.
      xdg.dataFile."remmina/gewismgmt.remmina" = {
        force = true;
        text = lib.generators.toINI {} {
          remmina = {
            name = "GEWISMGMT";
            group = "GEWIS";
            protocol = "RDP";
            # Only reachable over netbird-gewis: its split DNS maps this name to
            # the NetBird peer; public DNS gives an IP with 3389 closed.
            server = "GEWISMGMT.gewiswg.gewis.nl";
            username = "m10243";
            domain = "GEWISWG";
            # Dynamic resolution: the desktop follows the window size.
            scale = 2;
          };
        };
      };
    };
  };
}
