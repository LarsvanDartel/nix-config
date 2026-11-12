# services.bulwark — Bulwark JMAP webmail for Stalwart at webmail.lvdar.nl;
# signs in through kanidm's `stalwart` client.
{den, ...}: let
  # Option default and netbird-service target (see services/netbird.nix).
  defaultPort = 3002;
  domain = "webmail.lvdar.nl";
  # i18n/routing.ts SUPPORTED_LOCALES: the OAuth callback is
  # /<locale>/auth/callback, the locale coming from the browser.
  locales = ["ar" "ca" "cs" "da" "de" "en" "es" "et" "fa" "fr" "he" "hu" "it" "ja" "ko" "lv" "mn" "nb" "nl" "pl" "pt" "ro" "ru" "sk" "th" "tr" "uk" "vi" "zh" "zh-TW"];
in {
  den.aspects.services.bulwark = {
    includes = [den.aspects.services.netbird.client];

    # Own OIDC.
    netbird-service = {host, ...}: {
      webmail = {
        bearerAuth.enable = false;
        targets = [
          {
            peer = host.name;
            port = defaultPort;
          }
        ];
      };
    };

    # Tokens must come from Stalwart's own client: Stalwart accepts only that
    # `aud` (services/stalwart.nix).
    kanidm-provision.oauth2.stalwart.originUrl = map (l: "https://${domain}/${l}/auth/callback") locales;

    nixos = {
      config,
      lib,
      ...
    }: let
      inherit (lib.options) mkOption;
      inherit (lib.types) port;

      cfg = config.cosmos.services.bulwark;
      stalwart = config.cosmos.services.stalwart;
    in {
      options.cosmos.services.bulwark.port = mkOption {
        type = port;
        default = defaultPort;
      };

      config = {
        services.bulwark = {
          enable = true;
          inherit (cfg) port;
          # nixpkgs pins the package.
          updateCheck.enabled = false;

          settings = {
            # The browser calls JMAP here directly (CORS: services/stalwart.nix),
            # and Bulwark's server checks each sign-in against it too.
            jmapServerUrl = "https://${stalwart.hostname}";
            oauth = {
              enabled = true;
              # kanidm holds the passwords; Stalwart can't check them.
              only = true;
              clientId = "stalwart";
              issuerUrl = stalwart.issuerUrl;
            };
            autoSsoEnabled = true;
          };
        };

        # Static user, not DynamicUser: impermanence would persist the
        # /var/lib/private symlink and lose the generated session secret
        # (everyone signed out on every boot).
        users.users.bulwark.home = "/var/lib/bulwark";
        systemd.services.bulwark.serviceConfig = {
          DynamicUser = lib.mkForce false;
          # Exits 143 on SIGTERM: every stop would count as a failure.
          SuccessExitStatus = 143;
        };

        cosmos.services.netbird.client.exposedPorts = [cfg.port];

        cosmos.system.impermanence.persist.directories = [
          {
            directory = "/var/lib/bulwark";
            user = "bulwark";
            group = "bulwark";
            mode = "0700";
          }
        ];
      };
    };
  };
}
