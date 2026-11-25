# home.thunderbird — Thunderbird with mail, calendar and contact accounts and a generated theme
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
    # Light in both desktop modes; see docs/src/theming.md#switching.
    light = cosmosStyling.colors pkgs "light";
    colors = light.withHashtag;
    mix = pct: a: b: let
      channel = c: i: lib.fromHexString (builtins.substring i 2 c);
      blend = i:
        lib.fixedWidthString 2 "0" (lib.toLower (lib.toHexString
            ((channel a i * pct + channel b i * (100 - pct)) / 100)));
    in "#${blend 0}${blend 2}${blend 4}";
    pastel = slot: mix 33 light.${slot} light.base00;
    dark = cosmosStyling.colors pkgs "dark";
    sage = pct: mix pct dark.base0B light.base00;
    deep = pct: mix pct dark.base0B dark.base00;

    # Gecko ignores extensions.activeThemeID for dropped-in themes: enable it once under
    # Add-ons → Themes, and keep the id stable so it stays enabled.
    themeId = "cosmos@lvdar.nl";
    themeAddon = let
      header = pkgs.runCommand "thunderbird-header.jpg" {nativeBuildInputs = [pkgs.imagemagick];} ''
        magick ${config.cosmos.desktops.wallpapers.favourite} -resize 3000x \
          -gravity center -crop 3000x200+0+0 +repage \
          -fill '${deep 85}' -colorize 45% -quality 90 $out
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
            frame = deep 85;
            frame_inactive = deep 85;
            tab_background_text = base07;
            tab_selected = sage 90;
            tab_text = base07;
            tab_line = accent;
            tab_loading = accent;
            toolbar = sage 90;
            toolbar_text = base07;
            toolbar_top_separator = deep 70;
            toolbar_bottom_separator = deep 70;
            toolbar_field = sage 50;
            toolbar_field_text = base07;
            toolbar_field_border = deep 70;
            toolbar_field_focus = sage 35;
            toolbar_field_text_focus = base07;
            toolbar_field_border_focus = accent;
            toolbar_field_highlight = deep 85;
            toolbar_field_highlight_text = base07;
            button_background_hover = deep 90;
            button_background_active = deep 75;
            icons = base06;
            icons_attention = accent;
            popup = sage 50;
            popup_text = base07;
            popup_border = deep 70;
            popup_highlight = sage 90;
            popup_highlight_text = base07;
            sidebar = sage 75;
            sidebar_text = base07;
            sidebar_border = deep 70;
            sidebar_highlight = deep 90;
            sidebar_highlight_text = base07;
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

    # Signatures set no font-family (Calibri/Segoe UI fall back badly on Linux) and use PNG logos
    # via file://, never inline <svg> (Gmail/Outlook strip it); Thunderbird embeds them as cid:.
    logos = pkgs.runCommand "thunderbird-signature-logos" {nativeBuildInputs = [pkgs.resvg];} ''
      mkdir $out
      for name in tue gewis; do
        resvg --height 192 ${./_thunderbird}/logo-$name.svg $out/$name.png
      done
    '';
    signature = name: addresses: {
      showSignature = "append";
      htmlFormat = true;
      text =
        replaceStrings ["@addresses@" "@logo@"] [(concatMapStringsSep "<br>" mailto addresses) "file://${logos}/${name}.png"]
        (builtins.readFile ./_thunderbird/signature-${name}.html);
    };
    mailto = address: ''<a href="mailto:${address}" style="color:#1a1a1a;text-decoration:none;">${address}</a>'';

    # Merge with recursiveUpdate, not `//`: a shallow merge silently drops thunderbird.enable.
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
      # Keyed by attribute name, not Thunderbird's id1, id2…, so accounts survive a profile rebuild.
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
            # Custom OAuth against kanidm's `stalwart` client (services/stalwart.nix); one issuer, one token.
            # No issuerIdentifier: kanidm sends no RFC 9207 `iss`, so setting it rejects every response.
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
            # Plaintext in nix-secrets only to keep the addresses out of this public repo.
            aliases =
              map (alias: {
                address = alias;
                realName = "Lars van Dartel";
                signature = signature "gewis" [alias];
              })
              inputs.nix-secrets.gewis-aliases;
            thunderbird = {
              enable = true;
              # Shared mailboxes (SOGo's "Other Users") are unsubscribed: list everything, as SOGo does.
              settings = id: {
                "mail.server.server_${id}.using_subscription" = false;
              };
            };
          } (mkSignature "gewis" [address]);

        # Outlook leaves Junk Email unsubscribed, so both Outlook accounts list everything.
        tue = let
          address = "l.v.dartel@student.tue.nl";
        in
          recursiveUpdate {
            flavor = "outlook.office365.com";
            inherit address;
            realName = "Lars van Dartel";
            thunderbird = {
              enable = true;
              # Exchange already files SMTP-sent mail in Sent Items: a Thunderbird copy duplicates it, and
              # an unset fcc_folder falls back to <server>/Sent, which Thunderbird then creates.
              settings = id: {
                "mail.server.server_${id}.using_subscription" = false;
                "mail.identity.id_${id}.fcc" = false;
                "mail.identity.id_${id}.fcc_folder" = "imap://${replaceStrings ["@"] ["%40"] address}@outlook.office365.com/Sent Items";
                "mail.identity.id_${id}.fcc_folder_picker_mode" = "1";
              };
            };
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
          thunderbird = {
            enable = true;
            settings = id: {
              "mail.server.server_${id}.using_subscription" = false;
            };
          };
        };
      };

      # Calendar DAV has no custom OAuth: it takes a Stalwart app password, and Stalwart needs the
      # full name (`lvdar@lvdar.nl`) for login and URLs; a bare `lvdar` fails.
      accounts.calendar.accounts.lvdar = {
        primary = true;
        remote = {
          type = "caldav";
          url = "https://mail.lvdar.nl/dav/cal/lvdar%40lvdar.nl/default/";
          userName = "lvdar@lvdar.nl";
        };
        thunderbird = {
          enable = true;
          color = pastel "base05";
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
          color = pastel "base0B";
        };
      };

      # Written by services.birthday-calendar from the contacts.
      accounts.calendar.accounts.verjaardagen = {
        remote = {
          type = "caldav";
          url = "https://mail.lvdar.nl/dav/cal/lvdar%40lvdar.nl/verjaardagen/";
          userName = "lvdar@lvdar.nl";
        };
        thunderbird = {
          enable = true;
          readOnly = true;
          color = pastel "base08";
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
          color = pastel "base0A";
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
        # SOGo directory books: read-only, no CardDAV link (URL built from the web UI's id).
        # Host mail.gewis.nl: webmail.gewis.nl sits behind TU/e's WAF, which rejects REPORT.
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

              # paperless-ngx-uploader and the theme are unsigned builds (see thunderbird-addons.nix).
              "xpinstall.signatures.required" = false;

              "ui.systemUsesDarkTheme" = 0;

              # Identity-pref fallbacks cover every account; with reply on top, sig_bottom = false
              # puts the signature between the reply and the quote.
              "mail.identity.default.reply_on_top" = 1;
              "mail.identity.default.sig_bottom" = false;
            }
            # Calendars added by hand, keyed by registry id: their feed URLs carry tokens.
            // lib.mapAttrs' (id: color: lib.nameValuePair "calendar.registry.${id}.color" color) {
              "49aedaac-e948-44dd-9c56-01cf9aff81e9" = pastel "base0C"; # Canvas
              "d2c40193-0ebf-4bae-9bf9-9c5a29e84b4a" = pastel "base0D"; # TU/e
            }
            # The categories made in Thunderbird (calendar.categories.names).
            // lib.mapAttrs' (name: color: lib.nameValuePair "calendar.category.color.${name}" color) {
              birthday = colors.base0C;
              meeting = colors.base08;
              personal = colors.base0B;
              projects = colors.base0A;
              public_holiday = colors.base0E;
              school = colors.base09;
              sport = colors.base0D;
            };
        };
      };

      # Copied, not linked: Gecko notices a changed add-on only by mtime, which the store pins.
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
