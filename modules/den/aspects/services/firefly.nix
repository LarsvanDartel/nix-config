# services.firefly — Firefly III personal finance manager, plus its
# Enable Banking-backed data importer for automated bank sync.
#
# Enable Banking, not GoCardless (free tier closed to new signups July
# 2025): its free "restricted mode" only syncs accounts pre-authorised by
# hand in its own portal — exactly this deployment's shape, one person's own
# accounts.
#
# Firefly has no native OIDC, so it authenticates like MicroBin's write
# path: oauth2-proxy in front, nginx auth_request, Firefly trusting the
# result via remote_user_guard. Published through gaia *ungated* — kanidm
# SSO is already a full login, and stacking NetBird's check in front would
# mean authenticating twice for the same identity (see gaia.nix on
# immich/opencloud).
#
# The data importer is mesh-only and not in gaia.nix at all: opened by hand,
# occasionally — not worth a second oauth2-proxy instance (one systemd
# service per host; a second gated vhost needs its own kanidm client *and*
# proxy process). It still needs real TLS: Enable Banking's authorisation
# flow redirects the browser to a callback URL registered in its portal
# ahead of time, and that redirect is not guaranteed to tolerate plain HTTP.
# So: real wildcard cert, at a name that resolves only inside the mesh —
# same shape as idrac.lvdar.nl on pioneer.nix.
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
      importerCfg = config.services.firefly-iii-data-importer;
      notify = config.cosmos.system.notifyFailure;

      # Where a saved import configuration (config.json, downloaded from the
      # importer's web UI after a manual run) is placed by hand for the
      # auto-import timer below to find — no API to generate one; it captures
      # choices only a human makes once.
      importDir = "${importerCfg.dataDir}/import";

      autoImport = pkgs.writeShellApplication {
        name = "firefly-auto-import";
        runtimeInputs = [pkgs.coreutils];
        text = ''
          config="${importDir}/config.json"
          if [ ! -f "$config" ]; then
            echo "No $config yet: run an import once through the web UI, download its" \
                 "configuration there, and place it at that path to enable this timer."
            exit 0
          fi

          # Each of these is consumed by the artisan subprocess below via
          # `set -a`, not read directly in this script — shellcheck can't see
          # that, hence a disable per line rather than one at the top.
          set -a
          # shellcheck disable=SC2034
          APP_ENV=production
          # shellcheck disable=SC2034
          TZ=Europe/Amsterdam
          # shellcheck disable=SC2034
          FIREFLY_III_URL=https://${cfg.domain}
          # shellcheck disable=SC2034
          IMPORT_DIR_ALLOWLIST=${importDir}
          # shellcheck disable=SC2034
          ENABLE_BANKING_APP_ID="$(< "$CREDENTIALS_DIRECTORY/eb-app-id")"
          # shellcheck disable=SC2034
          ENABLE_BANKING_PRIVATE_KEY="$(< "$CREDENTIALS_DIRECTORY/eb-private-key")"
          # shellcheck disable=SC2034
          FIREFLY_III_ACCESS_TOKEN="$(< "$CREDENTIALS_DIRECTORY/access-token")"
          set +a

          exec ${importerCfg.package}/artisan importer:import "$config"
        '';
      };

      # The saved config.json carries an enable_banking_sessions id — the
      # same session the browser flow authorised — so the real consent expiry
      # (GET /sessions/{id}, access.valid_until) can be checked directly
      # rather than guessed from ASPSP ceilings. Verified live once: this
      # Rabobank grant is 90 days, not the 180-day maximum the bank allows.
      checkConsent = pkgs.writeShellApplication {
        name = "firefly-consent-check";
        runtimeInputs = with pkgs; [curl jq openssl coreutils];
        text = ''
          config="${importDir}/config.json"
          if [ ! -f "$config" ]; then
            echo "No $config yet; nothing to check."
            exit 0
          fi

          session_id="$(jq -r '.enable_banking_sessions[0] // empty' "$config")"
          if [ -z "$session_id" ]; then
            echo "config.json has no enable_banking_sessions; nothing to check."
            exit 0
          fi

          app_id="$(cat "$CREDENTIALS_DIRECTORY/eb-app-id")"
          now=$(date +%s)

          b64url() { base64 -w0 | tr '+/' '-_' | tr -d '='; }

          header=$(printf '{"typ":"JWT","alg":"RS256","kid":"%s"}' "$app_id" | b64url)
          payload=$(printf '{"iss":"enablebanking.com","aud":"api.enablebanking.com","iat":%d,"exp":%d}' "$now" "$((now + 300))" | b64url)
          signing_input="''${header}.''${payload}"
          signature=$(printf '%s' "$signing_input" | openssl dgst -sha256 -sign "$CREDENTIALS_DIRECTORY/eb-private-key" | b64url)
          jwt="''${signing_input}.''${signature}"

          response=$(curl -sS --max-time 20 -H "Authorization: Bearer $jwt" \
            "https://api.enablebanking.com/sessions/$session_id")
          valid_until=$(echo "$response" | jq -r '.access.valid_until // empty')
          status=$(echo "$response" | jq -r '.status // empty')

          if [ -z "$valid_until" ]; then
            echo "Could not read session expiry from Enable Banking: $response" >&2
            exit 1
          fi

          days_left=$(( ($(date -d "$valid_until" +%s) - now) / 86400 ))
          echo "session $session_id: status=$status, $days_left day(s) left ($valid_until)"

          # 14 days of runway: enough to notice and re-authorise by hand
          # (the same manual, browser-driven flow that created the session
          # in the first place — there is no way to renew it headlessly)
          # before the automatic import above starts silently doing nothing.
          if [ "$status" != "AUTHORIZED" ] || [ "$days_left" -le 14 ]; then
            password="$(cat "$CREDENTIALS_DIRECTORY/ntfy-password")"
            curl -sS --max-time 20 --retry 3 --retry-all-errors --retry-delay 10 \
              -u "${notify.user}:$password" \
              -H "Title: Firefly III: bank connection needs re-authorising" \
              -H "Priority: default" \
              -H "Tags: bank" \
              -d "Enable Banking session status is $status, valid_until $valid_until (~$days_left days left). Re-authorise it from https://${cfg.domain} (Automation > Import data) to keep the automatic import working." \
              "${notify.url}/${notify.topic}"
          fi
        '';
      };

      phpLocation = {
        socket,
        extraConfig ? "",
        # $request_filename is right for the "~ \.php$" location (it always
        # matches the literal /index.php tryFiles rewrote to), but wrong for
        # a prefix location like /api/ that never goes through tryFiles —
        # there it resolves to a nonexistent <root>/api/v1/whatever, so those
        # pass the real front controller path explicitly instead.
        scriptFilename ? "$request_filename",
      }: {
        extraConfig = ''
          include ${config.services.nginx.package}/conf/fastcgi_params;
          fastcgi_param SCRIPT_FILENAME ${scriptFilename};
          fastcgi_param modHeadersAvailable true;
          fastcgi_pass unix:${socket};

          # Neither app queues work — QUEUE_CONNECTION=sync in both — so an
          # import runs to completion inside the one request that started
          # it. Confirmed directly: a 373-transaction import took 33-37
          # minutes and *did* finish successfully server-side every time,
          # well past nginx's 60s default fastcgi_read_timeout — which had
          # already cut the client off, so the only visible symptom was a
          # progress bar that looked permanently stuck.
          fastcgi_read_timeout 3600s;
          fastcgi_send_timeout 3600s;

          ${extraConfig}
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
          # Not 8096: jellyfin's own port (jellyfin.nix) — two services
          # trying to bind it broke both; found only because jellyfin itself
          # started 400ing.
          default = 8098;
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

            # gaia terminates TLS and forwards plain HTTP, so without this
            # Laravel doesn't trust X-Forwarded-Proto and generates http://
            # links for everything — including the setup wizard's own form
            # action, which then fails to load entirely.
            TRUSTED_PROXIES = "**";

            # oauth2-proxy's X-Auth-Request-User/-Email land in these $_SERVER
            # keys via the fastcgi_params below — plain names, matching
            # Apache's mod_auth convention that remote_user_guard follows.
            AUTHENTICATION_GUARD = "remote_user_guard";
            AUTHENTICATION_GUARD_HEADER = "REMOTE_USER";
            AUTHENTICATION_GUARD_EMAIL = "REMOTE_USER_EMAIL";

            MAIL_MAILER = "smtp";
            MAIL_HOST = "smtp.protonmail.ch";
            MAIL_PORT = 587;
            MAIL_ENCRYPTION = "tls";
            MAIL_USERNAME = "firefly@lvdar.nl";
            MAIL_FROM = "firefly@lvdar.nl";
            MAIL_PASSWORD_FILE = config.sops.secrets."keys/firefly/smtp-token".path;
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
            # "restricted mode" — a manual human signup that can't be
            # provisioned from here. The app's callback URL, registered in
            # Enable Banking's portal, must be
            # https://${cfg.importerDomain}/eb-callback.
            ENABLE_BANKING_APP_ID_FILE = config.sops.secrets."keys/firefly/enable-banking-app-id".path;
            ENABLE_BANKING_PRIVATE_KEY_FILE = config.sops.secrets."keys/firefly/enable-banking-private-key".path;

            # Lets the CLI (`artisan importer:import`, used by the auto-import
            # timer below) read a config.json placed there — the same
            # allowlist the web UI's own file-upload path is restricted to.
            IMPORT_DIR_ALLOWLIST = importDir;
          };
        };

        systemd.tmpfiles.rules = [
          "d ${importDir} 0750 firefly-iii-data-importer firefly-iii-data-importer -"
        ];

        systemd.services.firefly-auto-import = {
          description = "Re-run Firefly III's saved Enable Banking import";
          after = ["network-online.target" "phpfpm-firefly-iii-data-importer.service"];
          wants = ["network-online.target"];
          serviceConfig = {
            Type = "oneshot";
            User = "firefly-iii-data-importer";
            Group = "firefly-iii-data-importer";
            WorkingDirectory = importerCfg.package;
            ReadWritePaths = [importerCfg.dataDir];
            LoadCredential = [
              "eb-app-id:${config.sops.secrets."keys/firefly/enable-banking-app-id".path}"
              "eb-private-key:${config.sops.secrets."keys/firefly/enable-banking-private-key".path}"
              "access-token:${config.sops.secrets."keys/firefly/importer-access-token".path}"
            ];
            ExecStart = lib.getExe autoImport;
          };
        };

        systemd.timers.firefly-auto-import = {
          description = "Daily automatic Firefly III bank import";
          wantedBy = ["timers.target"];
          timerConfig = {
            OnCalendar = "03:15";
            Persistent = true;
            RandomizedDelaySec = "10min";
          };
        };

        systemd.services.firefly-consent-check = {
          description = "Check Firefly III's Enable Banking session expiry";
          after = ["network-online.target"];
          wants = ["network-online.target"];
          serviceConfig = {
            Type = "oneshot";
            User = "firefly-iii-data-importer";
            Group = "firefly-iii-data-importer";
            LoadCredential = [
              "eb-app-id:${config.sops.secrets."keys/firefly/enable-banking-app-id".path}"
              "eb-private-key:${config.sops.secrets."keys/firefly/enable-banking-private-key".path}"
              "ntfy-password:${config.sops.secrets."keys/ntfy/password".path}"
            ];
            ExecStart = lib.getExe checkConsent;
          };
        };

        systemd.timers.firefly-consent-check = {
          description = "Weekly Firefly III bank consent expiry check";
          wantedBy = ["timers.target"];
          timerConfig = {
            OnCalendar = "weekly";
            Persistent = true;
            RandomizedDelaySec = "1h";
          };
        };

        # Both phpfpm sockets are 0660, group-owned by their own service user
        # — upstream only widens that to the "nginx" group when enableNginx
        # is on, which it isn't here (custom vhosts for the auth_request
        # gate). Without this nginx gets a bare "13: Permission denied" on
        # the socket — on firefly-iii specifically, only once an
        # authenticated request reaches the php location, since auth_request
        # intercepts every anonymous one first.
        users.users.nginx.extraGroups = ["firefly-iii" "firefly-iii-data-importer"];

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
          "keys/firefly/smtp-token".owner = "firefly-iii";
          # Created from Firefly's own UI (Profile → OAuth → Personal Access
          # Tokens) after the first SSO login — necessarily a manual,
          # after-the-fact step, since the token cannot exist before the
          # account it belongs to does.
          "keys/firefly/importer-access-token" = {owner = "firefly-iii-data-importer";};
          "keys/firefly/enable-banking-app-id".owner = "firefly-iii-data-importer";
          "keys/firefly/enable-banking-private-key".owner = "firefly-iii-data-importer";
        };

        # A second, hand-rolled oauth2-proxy rather than services.oauth2-proxy:
        # that option is a singleton and microbin.nix already configures it —
        # two callers setting different values conflict outright. This one
        # runs as its own systemd unit on a private port, with the nginx
        # wiring oauth2-proxy-nginx.nix would generate written by hand below.
        #
        # LoadCredential rather than running as a user with direct read
        # access: the client-secret file stays owned by kanidm (which also
        # reads it, for basicSecretFile — microbin.nix's identical pattern)
        # without this service sharing that group; systemd (root) reads it
        # and hands the content over privately.
        #
        # --whitelist-domain is required, not decorative: --reverse-proxy
        # validates every redirect target it is asked to honour against this
        # list, and an unset list is an empty one — rejecting every redirect
        # with "domain / port not in whitelist".
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
          # serves every request from.
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
              extraConfig = ''
                fastcgi_param REMOTE_USER $auth_user;
                fastcgi_param REMOTE_USER_EMAIL $auth_email;
              '';
            };

            # Firefly's REST API authenticates its own callers with a Bearer
            # token and was never meant to sit behind a browser SSO gate —
            # the importer's server-to-server calls have no session cookie
            # and got the 307-to-login redirect, a login page where JSON was
            # expected. Not just "/" with auth_request off: tryFiles rewrites
            # every request to /index.php internally, which re-enters the
            # same "~ \.php$" location, so the exemption has to live on a
            # location that calls fastcgi directly.
            "/api/" = phpLocation {
              socket = config.services.phpfpm.pools.firefly-iii.socket;
              scriptFilename = "$document_root/index.php";
              extraConfig = "auth_request off;";
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
              # replaces the matched "/oauth2/" prefix with it, so
              # /oauth2/start reaches oauth2-proxy as bare /start ("Rejecting
              # invalid redirect /start..."). Without it the full URI passes
              # through unchanged.
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
