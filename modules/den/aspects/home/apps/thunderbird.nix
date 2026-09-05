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

    # Reads ./_thunderbird/signature-<name>.html (standalone files, so
    # import-tree leaves them alone rather than trying to read them as a
    # flake-parts module — same convention as _hw/, _facter/, etc. — and so
    # each is a real, previewable HTML document rather than something read
    # through a wall of Nix escaping) and wires it into both prefs a
    # signature identity needs.
    #
    # recursiveUpdate rather than `//`, because both this and the account
    # attrset it's merged into set nested `thunderbird.*` keys — a shallow
    # merge would have the last one's `thunderbird` attrset clobber the
    # other's entirely, silently dropping `thunderbird.enable`.
    #
    # Deliberately no font-family in any of the files: Calibri/Segoe UI
    # don't exist on Linux, so naming them just meant falling through to
    # whatever generic sans-serif this system resolves to — which doesn't
    # match Thunderbird's own compose-window default font, and reads as
    # visibly not-the-same-font once actually sent. Leaving it unset makes
    # the signature inherit whatever font each message already composes in.
    #
    # The mark in the tue/gewis ones is sized to match the text beside it via
    # a live table row (the svg's height:100% resolves against the row's own
    # content height, so it never needs a guessed pixel value) — which only
    # works because the svg stays an inline replaced element. A `display:
    # block` here would pull it out of the inline box the td's
    # vertical-align:middle centers, and it would just sit at the top of the
    # cell instead — found that the hard way once already, worth not
    # reintroducing.
    mkSignature = name: {
      signature = {
        showSignature = "append";
        htmlFormat = true;
        text = builtins.readFile ./_thunderbird/signature-${name}.html;
      };

      # Otherwise Thunderbird prepends its own "-- " delimiter line above
      # every signature it inserts, which shows up as a stray dash or two
      # sitting above the greeting — these all already open with one.
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
      # Declarative rather than the id1, id2, ... Thunderbird itself assigned
      # by hand: those ids are order-of-creation state private to the
      # profile, so nothing here could target "the tue account" by name, only
      # "whichever account happened to be created fourth". Keying off the
      # attribute name below survives a profile rebuild, which matters
      # because .thunderbird's persistence is what this repo relies on, not a
      # guarantee upstream makes.
      #
      # No passwords here: Thunderbird's login manager and OAuth2 tokens live
      # in logins.json/key4.db, entirely separate from these prefs, and are
      # matched to an account by hostname+username — not by the account id —
      # so they keep working under the new ids untouched.
      accounts.email.accounts = {
        proton = recursiveUpdate {
          primary = true;
          address = "larsvandartel@proton.me";
          userName = "larsvandartel@proton.me";
          realName = "Lars van Dartel";
          # Proton Bridge (home.proton.mail-bridge), not Proton's own
          # servers: it terminates IMAP/SMTP on loopback with STARTTLS.
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

        # The `outlook.office365.com` flavor supplies host/port/TLS for both
        # protocols and, via programs/thunderbird.nix upstream, defaults both
        # auth methods to XOAUTH2 — all three of which have to match this
        # exactly, since it is the enterprise tenant TU/e issues student mail
        # through and not consumer Outlook.
        tue = recursiveUpdate {
          flavor = "outlook.office365.com";
          address = "l.v.dartel@student.tue.nl";
          realName = "Lars van Dartel";
          thunderbird.enable = true;
        } (mkSignature "tue");

        # Consumer Outlook.com, not the enterprise flavor above: the SMTP
        # host differs (smtp-mail.outlook.com vs. smtp.office365.com) and
        # nothing in upstream's flavor list covers it, so IMAP/SMTP and
        # XOAUTH2 are spelled out by hand instead.
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

          # Otherwise the four accounts above would still show up, just in
          # whatever order attrsOf happens to enumerate them, with the local
          # folders account (which is not and cannot be declared here) mixed
          # in at an arbitrary point instead of last.
          accountsOrder = ["proton" "gewis" "tue" "wsvw"];

          extensions = with pkgs.thunderbird-addons; [
            theme-ancient-time
            theme-nord-dark
            signature-switch
            paperless-ngx-uploader
          ];

          settings = {
            # Extensions dropped into the profile directory (as these are,
            # rather than installed through the Add-ons Manager) start out
            # disabled otherwise — Thunderbird treats an install it did not
            # see happen as suspicious. This is the pref the module's own
            # `extensions` docs point at to skip that manual re-enable step.
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
