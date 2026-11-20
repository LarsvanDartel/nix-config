# home.remmina — Remmina RDP client with the GEWISMGMT profile.
{den, ...}: {
  den.aspects.home.remmina = {
    # Saved passwords go to the Secret Service, not the profile.
    includes = [den.aspects.home.keyring];

    # netbird-gewis's DNS CNAMEs gewismgmt to its NetBird name, and its search
    # domain is net.nb.gewis.nl; MIT krb5 applies both by default, so FreeRDP
    # asked AD for TERMSRV/gewismgmt.net.nb.gewis.nl ("Server not found in
    # Kerberos database"). These keep the name as typed: TERMSRV/gewismgmt.
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

      # .config/freerdp holds the trusted RDP certificate fingerprints.
      cosmos.system.impermanence.persist.directories = [
        ".config/remmina"
        ".config/freerdp"
        ".local/share/remmina"
      ];

      # Global RDP prefs live in remmina.pref, which Remmina rewrites, so set
      # the key in place. Client keymap: printable keys go as the character the
      # local layout (Programmer Dvorak) produces; Windows would otherwise read
      # physical keys as US QWERTY. Ctrl/Alt/Super combos still go as physical
      # keys, i.e. QWERTY positions.
      home.activation.remminaPrefs = lib.hm.dag.entryAfter ["writeBoundary"] ''
        run mkdir -p ${lib.escapeShellArg "${config.xdg.configHome}/remmina"}
        run ${lib.getExe pkgs.crudini} --set \
          ${lib.escapeShellArg "${config.xdg.configHome}/remmina/remmina.pref"} \
          remmina_pref rdp_use_client_keymap 1
      '';

      # Remmina rewrites a profile on every connect, replacing the symlink, and
      # renames it to its `remmina_file_name` pattern (%G_%P_%N_%h); this name
      # already matches, and force puts the link back on the next activation.
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
            # \\tsclient\Downloads in the session.
            drive = "Downloads,${config.home.homeDirectory}/Downloads";
          };
        };
      };
    };
  };
}
