# home.thunderbird (+ the defaultApplication option; deployment sets it true)
{inputs, ...}: {
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
    inherit (lib.strings) concatMapStringsSep replaceStrings;

    cfg = config.cosmos.programs.thunderbird;

    # recursiveUpdate, not `//`: a shallow merge silently drops thunderbird.enable.
    # No font-family: Calibri/Segoe UI fall back to a mismatched sans on Linux.
    # Keep the tue/gewis svg inline (sized by height:100% of its row);
    # display:block pins it to the cell top. Do not reintroduce.
    # The signature files mark their contact line with @addresses@.
    signature = name: addresses: {
      showSignature = "append";
      htmlFormat = true;
      text =
        replaceStrings ["@addresses@"] [(concatMapStringsSep "<br>" mailto addresses)]
        (builtins.readFile ./_thunderbird/signature-${name}.html);
    };
    mailto = address: ''<a href="mailto:${address}" style="color:#1a1a1a;text-decoration:none;">${address}</a>'';

    mkSignature = name: addresses: {
      signature = signature name addresses;

      # These signatures already open with "-- ". Applies to aliases too.
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
            # client (services/stalwart.nix). Same issuer for IMAP and SMTP, so
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
        } (mkSignature "lvdar" []);

        gewis = let
          address = "m10243@gewis.nl";
        in
          recursiveUpdate {
            inherit address;
            userName = address;
            realName = "Lars van Dartel";
            imap.host = "imap.gewis.nl";
            imap.port = 993;
            smtp.host = "smtp.gewis.nl";
            smtp.port = 465;
            # Send-as addresses over this login. Plaintext in nix-secrets only to
            # keep them out of this public repo.
            aliases =
              map (alias: {
                address = alias;
                realName = "Lars van Dartel";
                signature = signature "gewis" [address alias];
              })
              inputs.nix-secrets.gewis-aliases;
            thunderbird = {
              enable = true;
              # Mailboxes shared with this account (SOGo's "Other Users", Dovecot's
              # `Shared/` namespace) are unsubscribed, so a subscribed-only listing
              # hides them. List everything, as SOGo does.
              settings = id: {
                "mail.server.server_${id}.using_subscription" = false;
              };
            };
          } (mkSignature "gewis" [address]);

        # Enterprise office365 tenant: the flavor supplies host/port/TLS/XOAUTH2.
        tue = let
          address = "l.v.dartel@student.tue.nl";
        in
          recursiveUpdate {
            flavor = "outlook.office365.com";
            inherit address;
            realName = "Lars van Dartel";
            thunderbird.enable = true;
          } (mkSignature "tue" [address]);

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
      # password. Stalwart 1.0 logs in and addresses accounts by full name
      # (`lvdar@lvdar.nl`); a bare `lvdar` fails both.
      accounts.calendar.accounts.lvdar = {
        primary = true;
        remote = {
          type = "caldav";
          url = "https://mail.lvdar.nl/dav/cal/lvdar%40lvdar.nl/default/";
          userName = "lvdar@lvdar.nl";
        };
        thunderbird.enable = true;
      };

      accounts.contact.accounts.lvdar = {
        remote = {
          type = "carddav";
          url = "https://mail.lvdar.nl/dav/card/lvdar%40lvdar.nl/default/";
          userName = "lvdar@lvdar.nl";
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

            # Identity-pref fallbacks, so they cover every account. With the
            # reply on top, sig_bottom = false puts the signature between the
            # reply and the quote instead of under the quote.
            "mail.identity.default.reply_on_top" = 1;
            "mail.identity.default.sig_bottom" = false;
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
