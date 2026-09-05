# services.firefly — Firefly III personal finance manager, plus its Enable
# Banking-backed data importer for automated bank sync (Rabobank included:
# Enable Banking covers 2500+ European PSD2 banks).
#
# Enable Banking, not GoCardless Bank Account Data (née Nordigen): GoCardless
# closed that free tier to new signups in July 2025. Enable Banking's free
# path is narrower — "restricted mode", which only ever syncs accounts you
# have pre-authorised by hand in its own portal, no business contract or
# eIDAS certificate needed — but that is exactly this deployment's shape: one
# person, their own accounts.
#
# Firefly has no native OIDC, unlike paperless/immich, so it authenticates
# through kanidm the way MicroBin's write path does: oauth2-proxy in front,
# nginx doing auth_request, and Firefly trusting the result via its
# remote_user_guard rather than its own local login form. Published through
# gaia *ungated* as a result — like immich/opencloud in the `shared` category
# there — rather than also behind a NetBird identity check: kanidm SSO is
# already a full login, and stacking NetBird's check in front of it would
# mean authenticating twice for the same identity, exactly the friction
# gaia.nix's own comment calls out for immich and opencloud.
#
# The data importer is mesh-only and not in gaia.nix at all: it's opened by
# hand, occasionally, to run an import — not a standing service worth a
# second oauth2-proxy instance (oauth2-proxy is one systemd service per host;
# a second gated vhost would need its own kanidm client *and* its own proxy
# process). It does need real TLS despite that, unlike a plain mesh-direct
# tool: Enable Banking's authorisation flow redirects the browser back to a
# callback URL registered in its portal ahead of time, and that redirect (via
# the bank's own site) is not guaranteed to tolerate a plain-HTTP target the
# way a same-mesh client hitting the app directly would be. So this is served
# under the real *.lvdar.nl wildcard at a name that resolves only inside the
# mesh — same shape as idrac.lvdar.nl on pioneer.nix, and for the same reason:
# a real cert needs a real name, and this one is not meant to be public.
{den, ...}: {
  den.aspects.services.firefly = {
    includes = with den.aspects.services; [nginx netbird.client];

    nixos = {
      config,
      lib,
      pkgs,
      ...
    }: let
      inherit (lib.options) mkOption;
      inherit (lib.types) port str;

      cfg = config.cosmos.services.firefly;

      phpLocation = {
        socket,
        extraFastcgiParams ? "",
      }: {
        extraConfig = ''
          include ${config.services.nginx.package}/conf/fastcgi_params;
          fastcgi_param SCRIPT_FILENAME $request_filename;
          fastcgi_param modHeadersAvailable true;
          fastcgi_pass unix:${socket};
          ${extraFastcgiParams}
        '';
      };
    in {
      options.cosmos.services.firefly = {
        domain = mkOption {
          type = str;
          default = "firefly.lvdar.nl";
        };

        importerDomain = mkOption {
          type = str;
          default = "firefly-import.lvdar.nl";
          description = ''
            Resolves only inside the mesh (see localRecords in endeavour.nix)
            to endeavour's own NetBird address — never published, but still a
            real name under the *.lvdar.nl wildcard so nginx can present a
            browser-trusted cert for Enable Banking's callback redirect.
          '';
        };

        importerPort = mkOption {
          type = port;
          default = 8096;
          description = ''
            Mesh-facing port for the data importer's own nginx vhost. Not
            proxied through gaia — see the header for why.
          '';
        };

        proxyPort = mkOption {
          type = port;
          default = 8097;
          description = ''
            Mesh-facing port nginx serves the main vhost on, and what gaia's
            netbird-proxy targets.
          '';
        };
      };

      config = {
        services.firefly-iii = {
          enable = true;
          virtualHost = cfg.domain;

          # Custom vhost below instead: the module's own generated one has
          # nowhere to hang the auth_request gate.
          enableNginx = false;

          settings = {
            APP_ENV = "production";
            APP_KEY_FILE = config.sops.secrets."keys/firefly/app-key".path;
            TZ = "Europe/Amsterdam";

            DB_CONNECTION = "pgsql";
            DB_DATABASE = "firefly-iii";
            DB_USERNAME = "firefly-iii";

            # oauth2-proxy's X-Auth-Request-User/-Email land in these two
            # PHP $_SERVER keys via the fastcgi_params below — plain names,
            # not HTTP_-prefixed, matching Apache's mod_auth convention that
            # remote_user_guard itself follows.
            AUTHENTICATION_GUARD = "remote_user_guard";
            AUTHENTICATION_GUARD_HEADER = "REMOTE_USER";
            AUTHENTICATION_GUARD_EMAIL = "REMOTE_USER_EMAIL";
          };
        };

        services.firefly-iii-data-importer = {
          enable = true;
          virtualHost = cfg.importerDomain;
          enableNginx = false;

          settings = {
            APP_ENV = "production";
            TZ = "Europe/Amsterdam";

            FIREFLY_III_URL = "https://${cfg.domain}";
            FIREFLY_III_ACCESS_TOKEN_FILE = config.sops.secrets."keys/firefly/importer-access-token".path;

            # From a free Enable Banking account (enablebanking.com) in
            # "restricted mode" — a manual, human signup that can't be
            # provisioned from here. The app's callback URL, registered in
            # Enable Banking's own portal, has to be set to
            # https://${cfg.importerDomain}/eb-callback.
            ENABLE_BANKING_APP_ID_FILE = config.sops.secrets."keys/firefly/enable-banking-app-id".path;
            ENABLE_BANKING_PRIVATE_KEY_FILE = config.sops.secrets."keys/firefly/enable-banking-private-key".path;
          };
        };

        # Peer auth over the unix socket, same as paperless/immich's own
        # database.createLocally: the postgres role name matches the OS user
        # each service already runs as, so nothing here needs a password.
        services.postgresql = {
          enable = true;
          ensureDatabases = ["firefly-iii"];
          ensureUsers = [
            {
              name = "firefly-iii";
              ensureDBOwnership = true;
            }
          ];
        };

        sops.secrets = {
          "keys/firefly/app-key" = {owner = "firefly-iii";};
          "keys/firefly/oauth-client-secret".owner = "kanidm";
          "keys/firefly/cookie-secret" = {};
          # Created from Firefly's own UI (Profile → OAuth → Personal Access
          # Tokens) after the first SSO login — necessarily a manual,
          # after-the-fact step, since the token cannot exist before the
          # account it belongs to does.
          "keys/firefly/importer-access-token" = {owner = "firefly-iii-data-importer";};
          "keys/firefly/enable-banking-app-id".owner = "firefly-iii-data-importer";
          "keys/firefly/enable-banking-private-key".owner = "firefly-iii-data-importer";
        };

        # A second, hand-rolled oauth2-proxy instance rather than
        # services.oauth2-proxy: that option is a singleton, and
        # microbin.nix already configures it (its own clientID, issuer,
        # redirect URL) for MicroBin's write-path gate. Two callers setting
        # different values on the same option conflict outright, so this one
        # runs as its own systemd unit on a private port instead, with the
        # nginx wiring oauth2-proxy-nginx.nix would otherwise generate
        # written out by hand below.
        #
        # LoadCredential rather than the module's usual pattern of running
        # as a user with direct read access: it lets the client-secret file
        # stay owned by kanidm (which also reads it, for
        # kanidm.provision.systems.oauth2.firefly.basicSecretFile — see
        # microbin.nix's identical secret) without this service needing to
        # share that group. systemd (root) reads the credential file itself
        # and hands the content to the service privately, regardless of the
        # original file's owner.
        #
        # --whitelist-domain is required, not decorative: --reverse-proxy
        # validates every redirect target it's asked to honour (including
        # the X-Auth-Request-Redirect header the /oauth2/ location below
        # sets) against this list, and an unset list means an empty one —
        # rejecting every redirect with "domain / port not in whitelist"
        # rather than the permissive default the flag's absence might imply.
        systemd.services.oauth2-proxy-firefly = {
          description = "oauth2-proxy for Firefly III";
          after = ["network.target" "kanidm.service"];
          wantedBy = ["multi-user.target"];
          serviceConfig = {
            DynamicUser = true;
            LoadCredential = [
              "client-secret:${config.sops.secrets."keys/firefly/oauth-client-secret".path}"
              "cookie-secret:${config.sops.secrets."keys/firefly/cookie-secret".path}"
            ];
            ExecStart = ''
              ${lib.getExe pkgs.oauth2-proxy} \
                --http-address=127.0.0.1:4181 \
                --provider=oidc \
                --oidc-issuer-url=https://auth.lvdar.nl/oauth2/openid/firefly \
                --client-id=firefly \
                --client-secret-file=%d/client-secret \
                --cookie-secret-file=%d/cookie-secret \
                --redirect-url=https://${cfg.domain}/oauth2/callback \
                --upstream=static://202 \
                --email-domain=* \
                --whitelist-domain=${cfg.domain} \
                --set-xauthrequest \
                --reverse-proxy \
                --trusted-proxy-ip=127.0.0.1/32 \
                --trusted-proxy-ip=::1/128 \
                --code-challenge-method=S256 \
                --skip-provider-button
            '';
            Restart = "on-failure";
            # OIDC discovery happens once at startup and can race kanidm
            # coming up; see microbin.nix's identical comment on its own
            # oauth2-proxy for why the pacing (not just the After=) matters.
            RestartSec = "10s";
          };
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

          # Server-level rather than only on "/": applies to the PHP location
          # below too, which Laravel's tryFiles rewrite is what actually
          # serves every request from (this vhost has no bare-file route
          # that isn't index.php).
          extraConfig = ''
            auth_request /oauth2/auth;
            error_page 401 = @redirectToAuth2ProxyLogin;
            auth_request_set $auth_user $upstream_http_x_auth_request_user;
            auth_request_set $auth_email $upstream_http_x_auth_request_email;

            proxy_set_header X-Forwarded-Proto https;
            absolute_redirect off;
          '';

          root = "${config.services.firefly-iii.package}/public";
          locations = {
            "/" = {
              tryFiles = "$uri $uri/ /index.php?$query_string";
              index = "index.php";
              extraConfig = "sendfile off;";
            };

            "~ \\.php$" = phpLocation {
              socket = config.services.phpfpm.pools.firefly-iii.socket;
              extraFastcgiParams = ''
                fastcgi_param REMOTE_USER $auth_user;
                fastcgi_param REMOTE_USER_EMAIL $auth_email;
              '';
            };

            # The three locations below are what oauth2-proxy-nginx.nix
            # generates for the shared instance; written by hand here since
            # this vhost talks to the dedicated one on :4181 instead.
            "= /oauth2/auth" = {
              proxyPass = "http://127.0.0.1:4181/oauth2/auth";
              extraConfig = ''
                auth_request off;
                proxy_set_header X-Scheme https;
                proxy_set_header Content-Length "";
                proxy_pass_request_body off;
              '';
            };

            "/oauth2/" = {
              # No trailing slash on the proxy_pass target: with one, nginx
              # replaces the matched "/oauth2/" prefix with it, so a request
              # for /oauth2/start reaches oauth2-proxy as bare /start —
              # observed directly as "Rejecting invalid redirect /start...".
              # Without the trailing slash the full URI, prefix included,
              # passes through unchanged.
              proxyPass = "http://127.0.0.1:4181";
              extraConfig = ''
                auth_request off;
                proxy_set_header X-Scheme https;
                proxy_set_header X-Auth-Request-Redirect https://$host$request_uri;
              '';
            };

            "@redirectToAuth2ProxyLogin" = {
              return = "307 https://${cfg.domain}/oauth2/start?rd=https://$host$request_uri";
              extraConfig = "auth_request off;";
            };
          };
        };

        # Mesh-direct, real TLS — see the header for why this one needs a
        # cert despite being mesh-only. exposedPorts opens the firewall on
        # the netbird interface alone; nothing on the LAN side needs this.
        cosmos.services.netbird.client.exposedPorts = [cfg.importerPort];

        # Resolvable only from inside the mesh — same mechanism idrac.lvdar.nl
        # uses on pioneer.nix, pointed at this host's own NetBird address
        # instead of a LAN one.
        cosmos.services.unbound.localRecords.${cfg.importerDomain} = "100.68.151.172";

        services.nginx.virtualHosts.${cfg.importerDomain} = {
          onlySSL = true;
          useACMEHost = "lvdar.nl";
          listen = [
            {
              addr = "0.0.0.0";
              port = cfg.importerPort;
              ssl = true;
            }
          ];

          root = "${config.services.firefly-iii-data-importer.package}/public";
          locations = {
            "/" = {
              tryFiles = "$uri $uri/ /index.php?$query_string";
              index = "index.php";
              extraConfig = "sendfile off;";
            };

            "~ \\.php$" = phpLocation {socket = config.services.phpfpm.pools.firefly-iii-data-importer.socket;};
          };
        };

        services.kanidm.provision = {
          groups.firefly-users = {
            overwriteMembers = false;
            members = ["lvdar"];
          };

          systems.oauth2.firefly = {
            displayName = "Firefly III";
            basicSecretFile = config.sops.secrets."keys/firefly/oauth-client-secret".path;
            originUrl = "https://${cfg.domain}/oauth2/callback";
            originLanding = "https://${cfg.domain}";
            scopeMaps.firefly-users = ["openid" "profile" "email"];
            preferShortUsername = true;
          };
        };

        cosmos.system.impermanence.persist.directories = [
          {
            directory = config.services.firefly-iii.dataDir;
            user = "firefly-iii";
            group = "firefly-iii";
            mode = "0710";
          }
          {
            directory = config.services.firefly-iii-data-importer.dataDir;
            user = "firefly-iii-data-importer";
            group = "firefly-iii-data-importer";
            mode = "0700";
          }
        ];
      };
    };
  };
}
