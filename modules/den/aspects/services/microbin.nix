# services.microbin — pastebin and small-file drop, public to read and OIDC to
#
# Reads public, writes OIDC-gated: a paste exists to be handed to someone, so
# reads must work without an account and writes must not. MicroBin has no
# OIDC and no plugin surface, so the split is made in front of it —
# oauth2-proxy against kanidm, nginx routing. The fleet's first forward-auth.
#
# MicroBin binds loopback and nginx is the only thing that can reach it; the
# mesh-facing port is nginx's `proxyPort`, which is what gaia's netbird-proxy
# targets. Publishing MicroBin's own port would let any mesh peer POST
# straight past the gate. Hence a deliberate exception to "an edge-terminated
# host has nothing for a local vhost to do": here the vhost does
# authorisation, not TLS.
#
# The route split was derived by probing a running MicroBin, not reading its
# source, because two things are not what they look like:
#
#   * `POST /upload/` — trailing slash — creates a pasta just like `POST
#     /upload`. Opening `/upload/` as a prefix so pasta *views* work would
#     also open an unauthenticated write endpoint — hence `limit_except GET
#     HEAD` on every public location.
#   * MICROBIN_SHORT_PATH does not move generated links onto `/p/`: after
#     creating a pasta MicroBin redirects to `/upload/{id}`, so `/upload/`
#     must be readable or every link it hands out is dead.
#
# The list below is an allow-list: anything not named is authenticated,
# which fails safely when MicroBin grows a route.
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

    # Readable without an account, and readable *only*: limit_except turns the
    # trailing-slash write path into a 403 rather than a pasta.
    publicRead = {
      proxyPass = backend;
      extraConfig = ''
        auth_request off;
        limit_except GET HEAD {
          deny all;
        }
      '';
    };

    # The password prompts for private pastas. These take a POST, so they
    # cannot use publicRead — but the POST only reveals a pasta whose password
    # the visitor already has, which is a read by another name.
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

          # Loopback, overriding the module's mkDefault "0.0.0.0". nginx is the
          # only thing that may reach MicroBin; see the header.
          MICROBIN_BIND = "127.0.0.1";

          MICROBIN_MAX_FILE_SIZE_UNENCRYPTED_MB = cfg.maxFileSizeMiB;

          # /list and /pastalist still answer 200 with this off, they just
          # render nothing (verified — a 200 reads like a leak).
          # Authenticated regardless: neither is on the allow-list.
          MICROBIN_LIST_SERVER = false;

          # Load-bearing for URL stability, not just aesthetics: IDs are
          # decoded according to this setting, so flipping it later makes every
          # existing link resolve to the wrong pasta or to nothing.
          MICROBIN_HASH_IDS = true;

          # Offered in the UI, not forced: encrypted pastas are decrypted in
          # the browser, so the server never holds the key.
          MICROBIN_ENCRYPTION_CLIENT_SIDE = true;

          MICROBIN_ENABLE_BURN_AFTER = true;
          MICROBIN_HIGHLIGHTSYNTAX = true;
          MICROBIN_QR = true;

          # Telemetry is already off by upstream default; this is the other
          # outbound call it makes on its own.
          MICROBIN_DISABLE_UPDATE_CHECKING = true;
        };
      };

      # A static user, not the module's DynamicUser. DynamicUser+
      # StateDirectory puts state in /var/lib/private/microbin behind a
      # symlink at the visible path — persisting the visible path would
      # persist the symlink and lose every pasta on the next boot: silent
      # total data loss, not a permissions error. Same trap as ollama.nix.
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

      # MicroBin's admin page only. There is deliberately no uploader password:
      # creating a pasta is gated by kanidm in front, not by a shared secret
      # typed into a form.
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

        # The *File forms, not the plain ones: `clientSecret` and
        # `cookie.secret` are removed options, and with abort-on-warn a
        # removed option is a build failure rather than a nudge. systemd loads
        # both as credentials, so neither value reaches the store and neither
        # file needs to be readable by the service user.
        clientSecretFile = config.sops.secrets."keys/microbin/oauth-client-secret".path;
        cookie.secretFile = config.sops.secrets."keys/microbin/cookie-secret".path;

        redirectURL = "https://${cfg.domain}/oauth2/callback";
        setXauthrequest = true;
        reverseProxy = true;

        # Required once reverseProxy is on: unset, oauth2-proxy trusts
        # X-Forwarded-* from 0.0.0.0/0, which would let anyone who can reach it
        # claim any scheme or client address. nginx on loopback is the only
        # thing that can, and the only thing that should. Leaving this out is
        # also a hard build failure here, since abort-on-warn is set.
        trustedProxyIP = ["127.0.0.1/32" "::1/128"];

        # kanidm's scope map is the real membership check — a user outside the
        # mapped group cannot obtain a token at all — so there is nothing left
        # for oauth2-proxy to filter on.
        email.domains = ["*"];

        # PKCE is opt-in here and off by default, which kanidm — which
        # enforces it — rejects at the authorise step ("No PKCE code
        # challenge was provided with client in enforced PKCE mode"),
        # surfacing to the browser as a bare invalid_request. Deliberately
        # not allowInsecureClientDisablePkce as jellyfin and traccar each
        # had to; this is the other, better way to satisfy the requirement.
        extraConfig.code-challenge-method = "S256";

        nginx = {
          domain = cfg.domain;
          virtualHosts.${cfg.domain} = {};
        };
      };

      # oauth2-proxy performs OIDC discovery once, at startup, and exits if
      # it fails. The issuer is the *public* name, so that request must leave
      # this host, cross the mesh, pass gaia's proxy and land on kanidm —
      # none of which is true in the first seconds of a boot. On 2026-08-30
      # it got nginx's 502, and Restart=always with the 100ms default
      # RestartSec spent NixOS's whole five-restart budget inside half a
      # second and gave up for good; microbin served 500s until restarted by
      # hand. Retry slowly and long enough for the fleet to finish coming up;
      # ordering after kanidm removes the most common part of the race.
      systemd.services.oauth2-proxy = {
        after = ["kanidm.service"];
        serviceConfig.RestartSec = "10s";
        unitConfig = {
          StartLimitIntervalSec = "15min";
          StartLimitBurst = 60;
        };
      };

      services.nginx.virtualHosts.${cfg.domain} = {
        # Plain HTTP on the mesh: gaia terminates TLS and forwards here.
        listen = [
          {
            addr = "0.0.0.0";
            port = cfg.proxyPort;
          }
        ];

        locations = {
          # Everything unlisted lands here and is authenticated. That includes
          # the index (which is the paste form), `= /upload` (the create POST),
          # /remove/, /edit/, /list and the admin page.
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

          # Pasta views. GET only — see the header for why the trailing slash
          # matters here.
          "/upload/" = publicRead;

          # The create POST, authenticated. Not redundant with
          # `location /`: the `/upload/` prefix above makes nginx answer
          # bare `/upload` with its own 301 to `/upload/`, and it does that
          # *before* auth_request runs. The form posts to `/upload`, so
          # without this every submission is redirected, downgraded to GET
          # by the browser, and lands on a read-only path — safe, but the
          # paste button did not work.
          "= /upload".proxyPass = backend;

          "/auth/" = publicForm;
          "/auth_raw/" = publicForm;
          "/auth_file/" = publicForm;

          # Same correction as X-Forwarded-Proto below, for the login
          # redirect the oauth2-proxy nginx module generates: it interpolates
          # $scheme, http on this side of the edge, and would send the
          # visitor to a URL gaia does not serve.
          "@redirectToAuth2ProxyLogin".return =
            mkForce "307 https://${cfg.domain}/oauth2/start?rd=https://$host$request_uri";
        };

        # The proxy sees plain HTTP, but the browser is on https. Without this
        # the upstream builds its callback from $scheme and sends the visitor
        # to an http:// URL that gaia does not serve.
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
