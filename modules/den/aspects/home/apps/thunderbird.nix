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

    # recursiveUpdate, not `//`: a shallow merge silently drops thunderbird.enable.
    # No font-family: Calibri/Segoe UI fall back to a mismatched sans on Linux.
    # Keep the tue/gewis svg inline (sized by height:100% of its row);
    # display:block pins it to the cell top. Do not reintroduce.
    mkSignature = name: {
      signature = {
        showSignature = "append";
        htmlFormat = true;
        text = builtins.readFile ./_thunderbird/signature-${name}.html;
      };

      # These signatures already open with "-- ".
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
      # Keyed by attribute name, not Thunderbird's order-of-creation id1, id2,
      # so accounts survive a profile rebuild.
      accounts.email.accounts = {
        lvdar = recursiveUpdate {
          primary = true;
          address = "lars@lvdar.nl";
          # Stalwart's account name (kanidm's short username), not the address.
          userName = "lvdar";
          realName = "Lars van Dartel";
          imap = {
            host = "mail.lvdar.nl";
            port = 993;
            authentication = "xoauth2";
          };
          smtp = {
            host = "mail.lvdar.nl";
            port = 465;
            authentication = "xoauth2";
          };
          thunderbird = {
            enable = true;
            # Thunderbird's custom OAuth (155+) against kanidm's `stalwart`
            # client (services/kanidm.nix). Same issuer for IMAP and SMTP, so
            # both share one refresh token. No issuerIdentifier: kanidm sends
            # no RFC 9207 `iss`, and setting it rejects every response.
            settings = id: let
              oauth = prefix: {
                "${prefix}.oauth2.useCustomDetails" = true;
                "${prefix}.oauth2.issuer" = "auth.lvdar.nl";
                "${prefix}.oauth2.clientId" = "stalwart";
                "${prefix}.oauth2.authorizationEndpoint" = "https://auth.lvdar.nl/ui/oauth2";
                "${prefix}.oauth2.tokenEndpoint" = "https://auth.lvdar.nl/oauth2/token";
                "${prefix}.oauth2.scopes" = "openid profile email";
                "${prefix}.oauth2.usePKCE" = true;
              };
            in
              oauth "mail.server.server_${id}" // oauth "mail.smtpserver.smtp_${id}";
          };
        } (mkSignature "lvdar");

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

        # Enterprise office365 tenant: the flavor supplies host/port/TLS/XOAUTH2.
        tue = recursiveUpdate {
          flavor = "outlook.office365.com";
          address = "l.v.dartel@student.tue.nl";
          realName = "Lars van Dartel";
          thunderbird.enable = true;
        } (mkSignature "tue");

        # Consumer Outlook.com: SMTP host differs and no flavor covers it.
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

      # Thunderbird's calendar has no custom OAuth: DAV takes a Stalwart app
      # password.
      accounts.calendar.accounts.lvdar = {
        primary = true;
        remote = {
          type = "caldav";
          url = "https://mail.lvdar.nl/dav/cal/lvdar/default/";
          userName = "lvdar";
        };
        thunderbird.enable = true;
      };

      accounts.contact.accounts.lvdar = {
        remote = {
          type = "carddav";
          url = "https://mail.lvdar.nl/dav/card/lvdar/default/";
          userName = "lvdar";
        };
        thunderbird.enable = true;
      };

      programs.thunderbird = {
        enable = true;

        profiles.default = {
          isDefault = true;

          # Otherwise the undeclarable local-folders account lands arbitrarily.
          accountsOrder = ["lvdar" "gewis" "tue" "wsvw"];

          extensions = with pkgs.thunderbird-addons; [
            theme-ancient-time
            theme-nord-dark
            signature-switch
            paperless-ngx-uploader
          ];

          settings = {
            # Store-dropped extensions start disabled otherwise.
            "extensions.autoDisableScopes" = 0;

            "extensions.activeThemeID" = pkgs.thunderbird-addons.theme-ancient-time.addonId;

            # paperless-ngx-uploader is unsigned (ships from GitHub, see
            # thunderbird-addons.nix); all other add-ons arrive via nix.
            "xpinstall.signatures.required" = false;
          };
        };
      };

      cosmos.system.impermanence.persist.directories = [".thunderbird"];

      xdg.mimeApps = mkIf cfg.defaultApplication {
        enable = true;
        # mailto: home.zen's setAsDefaultBrowser claims it too (via mkDefault).
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
