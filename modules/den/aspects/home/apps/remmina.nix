# home.remmina — Remmina RDP client with the GEWISMGMT profile.
{den, ...}: {
  den.aspects.home.remmina = {
    # Saved passwords go to the Secret Service, not the profile.
    includes = [den.aspects.home.keyring];

    # Keeps the SPN as typed (TERMSRV/gewismgmt): netbird-gewis's CNAME and search domain
    # would otherwise make krb5 ask AD for a principal it does not have.
    provides.to-hosts.nixos = {
      security.krb5 = {
        enable = true;
        settings.libdefaults = {
          dns_canonicalize_hostname = "fallback";
          # Literal quotes: a bare empty value is a krb5.conf syntax error.
          qualify_shortname = ''""'';
        };
      };
      # security.krb5 would otherwise add Kerberos to the login PAM stack.
      security.pam.krb5.enable = false;
    };

    homeManager = {
      config,
      lib,
      pkgs,
      ...
    }: {
      services.remmina = {
        enable = true;
        systemdService.enable = false;
      };

      cosmos.system.impermanence.persist.directories = [
        ".config/remmina"
        ".config/freerdp"
        ".local/share/remmina"
      ];

      # Remmina rewrites remmina.pref, so set the key in place. Client keymap: printable keys
      # follow the local Dvorak layout; Ctrl/Alt/Super combos stay physical (QWERTY).
      home.activation.remminaPrefs = lib.hm.dag.entryAfter ["writeBoundary"] ''
        run mkdir -p ${lib.escapeShellArg "${config.xdg.configHome}/remmina"}
        run ${lib.getExe pkgs.crudini} --set \
          ${lib.escapeShellArg "${config.xdg.configHome}/remmina/remmina.pref"} \
          remmina_pref rdp_use_client_keymap 1
      '';

      # Remmina replaces the symlink on connect and renames it to %G_%P_%N_%h; this name
      # matches, and force restores the link on the next activation.
      xdg.dataFile."remmina/gewis_rdp_gewismgmt_gewismgmt.remmina" = {
        force = true;
        text = lib.generators.toINI {} {
          remmina = {
            name = "GEWISMGMT";
            group = "GEWIS";
            protocol = "RDP";
            # Only reachable over netbird-gewis, whose DNS resolves it.
            server = "gewismgmt";
            username = "a10243";
            # The DNS realm, not the NetBIOS name: the server blocks NTLM, and
            # Kerberos finds the KDC through this realm's SRV records.
            domain = "GEWISWG.GEWIS.NL";
            # Dynamic resolution: the desktop follows the window size.
            scale = 2;
            # Remmina's default (0) turns off font smoothing, themes and more.
            quality = 9;
            network = "autodetect";
            # Win key, Alt+Tab and Super+… go to Windows; Right Ctrl toggles.
            keyboard_grab = 1;
            drive = "Downloads,${config.home.homeDirectory}/Downloads";
          };
        };
      };
    };
  };
}
