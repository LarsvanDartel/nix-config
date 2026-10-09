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
        proton = recursiveUpdate {
          primary = true;
          address = "larsvandartel@proton.me";
          userName = "larsvandartel@proton.me";
          realName = "Lars van Dartel";
          # Bridge sends as any address of the account; no separate config.
          aliases = [
            {
              address = "lars@lvdar.nl";
              realName = "Lars van Dartel";
            }
          ];
          # Via Proton Bridge (home.proton.mail-bridge).
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

      programs.thunderbird = {
        enable = true;

        profiles.default = {
          isDefault = true;

          # Otherwise the undeclarable local-folders account lands arbitrarily.
          accountsOrder = ["proton" "gewis" "tue" "wsvw"];

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
