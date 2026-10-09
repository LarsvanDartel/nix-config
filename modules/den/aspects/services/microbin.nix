# services.microbin — pastebin and small-file drop, public to read and OIDC to write.
#
# MicroBin has no auth hooks, so oauth2-proxy (kanidm) + nginx gate writes.
# MicroBin binds loopback; gaia's netbird-proxy must target nginx's
# `proxyPort`, never MicroBin's own port, or mesh peers bypass the gate.
#
# Routes below are an allow-list (unlisted = authenticated). Traps found by
# probing: `POST /upload/` also creates a pasta (hence `limit_except GET HEAD`
# on public locations), and MicroBin redirects new pastas to `/upload/{id}`,
# so `/upload/` must be readable.
{...}: {
  den.aspects.services.microbin.nixos = {
    config,
    lib,
    ...
  }: let
    inherit (lib.options) mkOption;
    inherit (lib.types) bool port str;
    inherit (lib.modules) mkForce;

    cfg = config.cosmos.services.microbin;
    dataDir = config.services.microbin.dataDir;

    backend = "http://127.0.0.1:${toString cfg.port}";

    # limit_except turns the trailing-slash write path into a 403.
    publicRead = {
      proxyPass = backend;
      extraConfig = ''
        auth_request off;
        limit_except GET HEAD {
          deny all;
        }
      '';
    };

    # Private-pasta password prompts: a POST, but it only reveals a pasta the
    # visitor already has the password for.
    publicForm = {
      proxyPass = backend;
      extraConfig = "auth_request off;";
    };
  in {
    options.cosmos.services.microbin = {
      expose = mkOption {
        type = bool;
        default = false;
      };

      port = mkOption {
        type = port;
        default = 8081;
        description = "Loopback port MicroBin itself listens on. Not published.";
      };

      proxyPort = mkOption {
        type = port;
        default = 8087;
        description = ''
          The mesh-facing port nginx serves this vhost on, and the one gaia's
          netbird-proxy must target. Publishing `port` instead would bypass
          the authentication in front of the write routes.
        '';
      };

      domain = mkOption {
        type = str;
        default = "bin.lvdar.nl";
        description = ''
          Public name. Also MICROBIN_PUBLIC_PATH: MicroBin builds the URLs it
          hands back — the copy button, the QR code, the raw link — from this
          rather than from the request, so behind a proxy an unset or wrong
          value produces pastas whose own links point at the internal address.
        '';
      };

      adminUser = mkOption {
        type = str;
        default = "lvdar";
        description = "Username for MicroBin's own admin page.";
      };

      maxFileSizeMiB = mkOption {
        type = lib.types.ints.positive;
        default = 256;
        description = ''
          Cap on unencrypted uploads. Upstream's default is far larger, and
          while writes are authenticated the stored files are served to anyone
          with the link — so this bounds what the box can be made to host.
        '';
      };
    };

    config = {
      services.microbin = {
        enable = true;
        passwordFile = config.sops.templates."microbin.env".path;
        settings = {
          MICROBIN_PORT = cfg.port;
          MICROBIN_PUBLIC_PATH = "https://${cfg.domain}";

          # Overrides the module's "0.0.0.0"; see header.
          MICROBIN_BIND = "127.0.0.1";

          MICROBIN_MAX_FILE_SIZE_UNENCRYPTED_MB = cfg.maxFileSizeMiB;

          # /list and /pastalist still answer 200 (empty) with this off.
          MICROBIN_LIST_SERVER = false;

          # Never flip: IDs are decoded per this setting, breaking existing links.
          MICROBIN_HASH_IDS = true;

          MICROBIN_ENCRYPTION_CLIENT_SIDE = true;

          MICROBIN_ENABLE_BURN_AFTER = true;
          MICROBIN_HIGHLIGHTSYNTAX = true;
          MICROBIN_QR = true;

          MICROBIN_DISABLE_UPDATE_CHECKING = true;
        };
      };

      # Not DynamicUser: persisting the visible path of a /var/lib/private
      # state dir persists only the symlink — silent total data loss.
      users.users.microbin = {
        isSystemUser = true;
        group = "microbin";
        home = dataDir;
      };
      users.groups.microbin = {};

      systemd.services.microbin.serviceConfig = {
        DynamicUser = mkForce false;
        User = "microbin";
        Group = "microbin";
      };

      # Deliberately no uploader password; kanidm gates creation.
      sops.secrets = {
        "keys/microbin/admin-password" = {};
        "keys/microbin/oauth-client-secret".owner = "kanidm";
        "keys/microbin/cookie-secret" = {};
      };

      sops.templates."microbin.env" = {
        content = ''
          MICROBIN_ADMIN_USERNAME=${cfg.adminUser}
          MICROBIN_ADMIN_PASSWORD=${config.sops.placeholder."keys/microbin/admin-password"}
        '';
        owner = "microbin";
      };

      services.oauth2-proxy = {
        enable = true;
        provider = "oidc";
        oidcIssuerUrl = "https://auth.lvdar.nl/oauth2/openid/microbin";
        clientID = "microbin";

        # The plain forms are removed options (build failure under abort-on-warn).
        clientSecretFile = config.sops.secrets."keys/microbin/oauth-client-secret".path;
        cookie.secretFile = config.sops.secrets."keys/microbin/cookie-secret".path;

        redirectURL = "https://${cfg.domain}/oauth2/callback";
        setXauthrequest = true;
        reverseProxy = true;

        # Unset, oauth2-proxy trusts X-Forwarded-* from anywhere.
        trustedProxyIP = ["127.0.0.1/32" "::1/128"];

        # kanidm's scope map is the real membership check.
        email.domains = ["*"];

        # kanidm enforces PKCE; preferred over allowInsecureClientDisablePkce.
        extraConfig.code-challenge-method = "S256";

        nginx = {
          domain = cfg.domain;
          virtualHosts.${cfg.domain} = {};
        };
      };

      # Discovery happens once at startup against the public issuer (via the
      # mesh and gaia), which fails early in boot; default restart settings
      # exhausted the start limit in <1s and left microbin down (2026-08-30).
      systemd.services.oauth2-proxy = {
        after = ["kanidm.service"];
        serviceConfig.RestartSec = "10s";
        unitConfig = {
          StartLimitIntervalSec = "15min";
          StartLimitBurst = 60;
        };
      };

      services.nginx.virtualHosts.${cfg.domain} = {
        listen = [
          {
            addr = "0.0.0.0";
            port = cfg.proxyPort;
          }
        ];

        locations = {
          "/".proxyPass = backend;

          "/p/" = publicRead;
          "/u/" = publicRead;
          "/url/" = publicRead;
          "/raw/" = publicRead;
          "/qr/" = publicRead;
          "/file/" = publicRead;
          "/secure_file/" = publicRead;
          "/archive/" = publicRead;
          "/static/" = publicRead;

          "/upload/" = publicRead;

          # Not redundant with `/`: the `/upload/` prefix makes nginx 301 bare
          # `/upload` before auth_request runs, breaking the create POST.
          "= /upload".proxyPass = backend;

          "/auth/" = publicForm;
          "/auth_raw/" = publicForm;
          "/auth_file/" = publicForm;

          # The module interpolates $scheme, which is http behind the edge.
          "@redirectToAuth2ProxyLogin".return =
            mkForce "307 https://${cfg.domain}/oauth2/start?rd=https://$host$request_uri";
        };

        extraConfig = ''
          proxy_set_header X-Forwarded-Proto https;

          # nginx builds absolute redirects from its own listen address — a
          # mesh port behind the edge — naming http://bin.lvdar.nl:8087/: a
          # dead link and a needless disclosure. Relative redirects resolve
          # against the public URL.
          absolute_redirect off;
        '';
      };

      services.kanidm.provision = {
        groups.microbin-users = {
          overwriteMembers = false;
          members = ["lvdar"];
        };

        systems.oauth2.microbin = {
          displayName = "MicroBin";
          basicSecretFile = config.sops.secrets."keys/microbin/oauth-client-secret".path;
          originUrl = "https://${cfg.domain}/oauth2/callback";
          originLanding = "https://${cfg.domain}";
          scopeMaps.microbin-users = ["openid" "profile" "email"];
          preferShortUsername = true;
        };
      };

      cosmos.system.impermanence.persist.directories = [
        {
          directory = dataDir;
          user = "microbin";
          group = "microbin";
          mode = "0750";
        }
      ];
    };
  };
}
