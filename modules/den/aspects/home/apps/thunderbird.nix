# home.thunderbird (+ the defaultApplication option; deployment sets it true)
{...}: {
  den.aspects.home.thunderbird.homeManager = {
    config,
    lib,
    pkgs,
    ...
  }: let
    inherit (lib.options) mkOption;
    inherit (lib.types) bool;
    inherit (lib.modules) mkIf;
    inherit (lib.attrsets) recursiveUpdate;

    cfg = config.cosmos.programs.thunderbird;

    # ./_thunderbird/signature-<name>.html: standalone files so import-tree
    # leaves them alone (same convention as _hw/, _facter/) and each stays a
    # previewable HTML document rather than Nix-escaped text.
    #
    # recursiveUpdate, not `//`: this and the account attrset both set nested
    # thunderbird.* keys — a shallow merge silently drops thunderbird.enable.
    #
    # Deliberately no font-family: Calibri/Segoe UI don't exist on Linux, so
    # naming them falls through to a generic sans that visibly mismatches the
    # compose font once sent. Unset, the signature inherits the message font.
    #
    # The tue/gewis mark is sized by a live table row (svg height:100% against
    # the row's own height) — works only while the svg stays an inline
    # replaced element; display:block pulls it out of the td's
    # vertical-align:middle box and it sits at the cell top. Do not
    # reintroduce.
    mkSignature = name: {
      signature = {
        showSignature = "append";
        htmlFormat = true;
        text = builtins.readFile ./_thunderbird/signature-${name}.html;
      };

      # Suppresses Thunderbird's "-- " delimiter — these signatures already
      # open with one.
      thunderbird.perIdentitySettings = id: {
        "mail.identity.id_${id}.suppress_signature_separator" = true;
      };
    };
  in {
    options.cosmos.programs.thunderbird.defaultApplication = mkOption {
      type = bool;
      default = false;
    };

    config = {
      # Keyed by attribute name, not Thunderbird's hand-assigned id1, id2, ...
      # (order-of-creation profile state): survives a profile rebuild, which
      # matters since .thunderbird persistence is this repo's reliance, not
      # an upstream guarantee.
      #
      # No passwords needed: OAuth2 tokens live in logins.json/key4.db and
      # match accounts by hostname+username, not id — they survive new ids.
      accounts.email.accounts = {
        proton = recursiveUpdate {
          primary = true;
          address = "larsvandartel@proton.me";
          userName = "larsvandartel@proton.me";
          realName = "Lars van Dartel";
          # Custom-domain address on the same Proton account — Bridge
          # accepts any address the account is allowed to send as, so no
          # separate SMTP/IMAP config; signature inherits from the
          # proton account above.
          aliases = [
            {
              address = "lars@lvdar.nl";
              realName = "Lars van Dartel";
            }
          ];
          # Via Proton Bridge (home.proton.mail-bridge): loopback
          # IMAP/SMTP with STARTTLS.
          imap = {
            host = "127.0.0.1";
            port = 1143;
            tls.useStartTls = true;
          };
          smtp = {
            host = "127.0.0.1";
            port = 1025;
            tls.useStartTls = true;
          };
          thunderbird.enable = true;
        } (mkSignature "proton");

        gewis = recursiveUpdate {
          address = "m10243@gewis.nl";
          userName = "m10243@gewis.nl";
          realName = "Lars van Dartel";
          imap.host = "imap.gewis.nl";
          imap.port = 993;
          smtp.host = "smtp.gewis.nl";
          smtp.port = 465;
          thunderbird.enable = true;
        } (mkSignature "gewis");

        # Enterprise office365 tenant (TU/e student mail), not consumer
        # Outlook: the flavor supplies host/port/TLS and upstream defaults
        # both auths to XOAUTH2 — all three must match this exactly.
        tue = recursiveUpdate {
          flavor = "outlook.office365.com";
          address = "l.v.dartel@student.tue.nl";
          realName = "Lars van Dartel";
          thunderbird.enable = true;
        } (mkSignature "tue");

        # Consumer Outlook.com, not the enterprise flavor: SMTP host differs
        # and no upstream flavor covers it, so IMAP/SMTP/XOAUTH2 by hand.
        wsvw = {
          address = "jeugd@wsvw.com";
          userName = "jeugd@wsvw.com";
          realName = "Jeugdcommissie WSVW";
          imap = {
            host = "outlook.office365.com";
            port = 993;
            authentication = "xoauth2";
          };
          smtp = {
            host = "smtp-mail.outlook.com";
            port = 587;
            authentication = "xoauth2";
            tls.useStartTls = true;
          };
          thunderbird.enable = true;
        };
      };

      programs.thunderbird = {
        enable = true;

        profiles.default = {
          isDefault = true;

          # Without this, attrsOf enumeration order decides, with the
          # undeclarable local-folders account mixed in at an arbitrary point.
          accountsOrder = ["proton" "gewis" "tue" "wsvw"];

          extensions = with pkgs.thunderbird-addons; [
            theme-ancient-time
            theme-nord-dark
            signature-switch
            paperless-ngx-uploader
          ];

          settings = {
            # Store-dropped extensions start disabled otherwise; the pref the
            # module's own `extensions` docs point at to skip the re-enable.
            "extensions.autoDisableScopes" = 0;

            # Selects Ancient Time as the active theme; nord-dark ships
            # alongside it, installed and available to switch to without
            # this being what's on screen by default.
            "extensions.activeThemeID" = pkgs.thunderbird-addons.theme-ancient-time.addonId;

            # paperless-ngx-uploader ships from GitHub rather than ATN (see
            # its own comment in thunderbird-addons.nix for why), so it
            # carries no AMO/ATN signature. Every other add-on in this
            # profile is an ATN-signed build arriving through the nix store
            # rather than a browse-and-install, so this lowers the check for
            # one already-vetted extension rather than for anything a user
            # could install by visiting a page.
            "xpinstall.signatures.required" = false;
          };
        };
      };

      cosmos.system.impermanence.persist.directories = [".thunderbird"];

      xdg.mimeApps = mkIf cfg.defaultApplication {
        enable = true;
        # Taken from thunderbird.desktop's own MimeType line. mailto matters
        # beyond tidiness: home.zen's setAsDefaultBrowser claims it too, so
        # without this a mailto: link opens the browser. These are plain
        # definitions and zen's are mkDefault, so these win.
        defaultApplications = let
          tb = ["thunderbird.desktop"];
        in {
          "x-scheme-handler/mailto" = tb;
          "message/rfc822" = tb;
          "text/calendar" = tb;
          "text/x-vcard" = tb;
        };
      };
    };
  };
}
