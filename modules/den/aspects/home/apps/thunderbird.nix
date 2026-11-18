# home.thunderbird (+ the defaultApplication option; deployment sets it true)
{
  inputs,
  cosmosStyling,
  ...
}: {
  den.aspects.home.thunderbird.homeManager = {
    config,
    lib,
    pkgs,
    ...
  }: let
    inherit (lib.options) mkOption;
    inherit (lib.types) bool;
    inherit (lib.modules) mkIf;
    inherit (lib.attrsets) mapAttrs recursiveUpdate;
    inherit (lib.strings) concatMapStringsSep replaceStrings;

    cfg = config.cosmos.programs.thunderbird;
    # Thunderbird stays light whatever the desktop mode
    # (ui.systemUsesDarkTheme below), so everything here uses the light
    # palette.
    colors = (cosmosStyling.colors pkgs "light").withHashtag;

    # The header is a band of the default wallpaper, faded towards the
    # background so the tab titles on it stay readable. Gecko installs every
    # dropped-in theme disabled and ignores extensions.activeThemeID for it:
    # enable it once under Add-ons → Themes; the stable id keeps it enabled.
    themeId = "cosmos@lvdar.nl";
    themeAddon = let
      header = pkgs.runCommand "thunderbird-header.jpg" {nativeBuildInputs = [pkgs.imagemagick];} ''
        magick ${config.cosmos.desktops.wallpapers.favourite} -resize 3000x \
          -gravity center -crop 3000x200+0+0 +repage \
          -fill '${colors.base00}' -colorize 45% -quality 90 $out
      '';
      accent = colors.${cosmosStyling.accent};
      manifest = pkgs.writeText "manifest.json" (builtins.toJSON {
        manifest_version = 2;
        name = "Cosmos (${cosmosStyling.theme})";
        version = "1.0";
        browser_specific_settings.gecko.id = themeId;
        theme = {
          images.theme_frame = "header.jpg";
          colors = with colors; {
            frame = base01;
            frame_inactive = base01;
            tab_background_text = base05;
            tab_selected = base00;
            tab_text = base05;
            tab_line = accent;
            tab_loading = accent;
            toolbar = base00;
            toolbar_text = base05;
            toolbar_top_separator = base02;
            toolbar_bottom_separator = base02;
            toolbar_field = base01;
            toolbar_field_text = base05;
            toolbar_field_border = base02;
            toolbar_field_focus = base01;
            toolbar_field_text_focus = base05;
            toolbar_field_border_focus = accent;
            toolbar_field_highlight = base02;
            toolbar_field_highlight_text = base06;
            button_background_hover = base02;
            button_background_active = base03;
            icons = base05;
            icons_attention = accent;
            popup = base01;
            popup_text = base05;
            popup_border = base02;
            popup_highlight = base02;
            popup_highlight_text = base06;
            sidebar = base01;
            sidebar_text = base05;
            sidebar_border = base02;
            sidebar_highlight = base02;
            sidebar_highlight_text = base06;
          };
          properties = {
            color_scheme = "light";
            content_color_scheme = "light";
          };
        };
      });
    in
      pkgs.runCommand "${themeId}.xpi" {nativeBuildInputs = [pkgs.zip];} ''
        mkdir src
        cp ${manifest} src/manifest.json
        cp ${header} src/header.jpg
        (cd src && zip -qX $out manifest.json header.jpg)
      '';

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
                signature = signature "gewis" [alias];
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
        thunderbird = {
          enable = true;
          color = colors.base05;
        };
      };

      # Written by services.holiday-calendar; local edits would be undone.
      accounts.calendar.accounts.feestdagen = {
        remote = {
          type = "caldav";
          url = "https://mail.lvdar.nl/dav/cal/lvdar%40lvdar.nl/feestdagen/";
          userName = "lvdar@lvdar.nl";
        };
        thunderbird = {
          enable = true;
          readOnly = true;
          color = colors.base0B;
        };
      };

      # Created by hand (MKCALENDAR): Stalwart calendars are account data.
      accounts.calendar.accounts.sailing = {
        remote = {
          type = "caldav";
          url = "https://mail.lvdar.nl/dav/cal/lvdar%40lvdar.nl/sailing/";
          userName = "lvdar@lvdar.nl";
        };
        thunderbird = {
          enable = true;
          color = colors.base0A;
        };
      };

      accounts.contact.accounts =
        {
          lvdar = {
            remote = {
              type = "carddav";
              url = "https://mail.lvdar.nl/dav/card/lvdar%40lvdar.nl/default/";
              userName = "lvdar@lvdar.nl";
            };
            thunderbird.enable = true;
          };
        }
        # SOGo's global (directory) address books: read-only, and SOGo shows no
        # CardDAV link for them; the URL is built from the id in the web UI's URL.
        # Host mail.gewis.nl, not webmail.gewis.nl: webmail sits behind TU/e's
        # WAF, which rejects REPORT, so cards never download. Plaintext in
        # nix-secrets, like the aliases.
        // mapAttrs (_: url: {
          remote = {
            type = "carddav";
            inherit url;
            userName = "m10243@gewis.nl";
          };
          thunderbird.enable = true;
        })
        inputs.nix-secrets.gewis-address-books;

      programs.thunderbird = {
        enable = true;

        profiles.default = {
          isDefault = true;

          # Otherwise the undeclarable local-folders account lands arbitrarily.
          accountsOrder = ["lvdar" "gewis" "tue" "wsvw"];

          extensions = with pkgs.thunderbird-addons; [
            signature-switch
            paperless-ngx-uploader
          ];

          settings =
            {
              # Store-dropped extensions start disabled otherwise.
              "extensions.autoDisableScopes" = 0;

              # paperless-ngx-uploader and the theme are unsigned (GitHub,
              # see thunderbird-addons.nix; built here); the rest arrive via
              # nix.
              "xpinstall.signatures.required" = false;

              "ui.systemUsesDarkTheme" = 0;

              # Identity-pref fallbacks, so they cover every account. With the
              # reply on top, sig_bottom = false puts the signature between the
              # reply and the quote instead of under the quote.
              "mail.identity.default.reply_on_top" = 1;
              "mail.identity.default.sig_bottom" = false;
            }
            # Calendars added by hand in Thunderbird, keyed by registry id:
            # their feed URLs carry tokens.
            // lib.mapAttrs' (id: color: lib.nameValuePair "calendar.registry.${id}.color" color) {
              "49aedaac-e948-44dd-9c56-01cf9aff81e9" = colors.base0C; # Canvas
              "d2c40193-0ebf-4bae-9bf9-9c5a29e84b4a" = colors.base0D; # TU/e
            };
        };
      };

      # A copy, not home-manager's store link: Gecko notices a changed add-on
      # only by its file's mtime, which the store pins at 1.
      home.activation.thunderbirdTheme = lib.hm.dag.entryAfter ["linkGeneration"] ''
        dest=${lib.escapeShellArg "${config.home.homeDirectory}/.thunderbird/default/extensions/${themeId}.xpi"}
        if ! cmp -s ${themeAddon} "$dest"; then
          run mkdir -p "$(dirname "$dest")"
          run install -m 644 ${themeAddon} "$dest"
        fi
      '';

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
