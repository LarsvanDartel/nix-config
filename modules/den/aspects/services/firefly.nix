# services.firefly — Firefly III personal finance manager, plus its
# Enable Banking-backed data importer for automated bank sync.
#
# Enable Banking, not GoCardless (free tier closed to new signups July 2025).
#
# No native OIDC: oauth2-proxy + nginx auth_request + remote_user_guard.
# Published through gaia *ungated* — kanidm SSO is already a full login.
#
# The data importer is mesh-only, not in gaia.nix, but still needs real TLS:
# Enable Banking's pre-registered callback redirect may not tolerate HTTP.
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

      # config.json is downloaded from the importer's web UI after a manual
      # run and placed here by hand — there is no API to generate one.
      importDir = "${importerCfg.dataDir}/import";

      autoImport = pkgs.writeShellApplication {
        name = "firefly-auto-import";
        runtimeInputs = [pkgs.coreutils pkgs.gnugrep];
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

          # config.json uses a sliding 30-day "range" window (not Firefly's
          # date-of-last-known-transaction "partial" mode), so every run
          # re-fetches transactions the previous run(s) already imported.
          # firefly-iii-data-importer logs each of those as an "error" entry
          # (app/Console/Commands/Import.php: any non-empty errors[] forces
          # exit code GENERAL_ERROR) even though `ignore_duplicate_transactions`
          # already told it to skip re-adding them — duplicate detection
          # working as intended still reads as a hard failure to systemd. Seen
          # daily since the config was created on 2026-09-05, paging over
          # ntfy every night for zero actual problem. Only escalate when some
          # of the reported errors are *not* duplicate skips.
          set +e
          output="$(${importerCfg.package}/artisan importer:import "$config" 2>&1)"
          status=$?
          set -e
          printf '%s\n' "$output"

          total_errors="$(printf '%s\n' "$output" | grep -oE 'Array contains [0-9]+ error\(s\)' | grep -oE '[0-9]+' || true)"
          # "Duplicate of transaction #" also shows up 2-3x per duplicate in
          # the submission-attempt DEBUG/ERROR lines above — only the final
          # "Import index N: ..." report line is one-per-array-entry, so
          # that's what has to line up with the declared error count.
          dup_errors="$(printf '%s\n' "$output" | grep -cE '^Import index [0-9]+: .*Duplicate of transaction #' || true)"
          total_errors="''${total_errors:-0}"
          dup_errors="''${dup_errors:-0}"

          if [ "$status" -ne 0 ] && [ "$total_errors" -gt 0 ] && [ "$total_errors" -eq "$dup_errors" ]; then
            echo "firefly-auto-import: $total_errors error(s) reported, all already-imported duplicates — not a real failure."
            exit 0
          fi
          exit "$status"
        '';
      };

      # Checks the real consent expiry via the session id in config.json
      # (this Rabobank grant is 90 days, not the 180-day ASPSP maximum).
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
        # $request_filename is wrong for prefix locations like /api/ that
        # skip tryFiles (nonexistent <root>/api/v1/...); pass the path instead.
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
          # Not 8096: jellyfin's port — binding both broke both.
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

          # Custom vhost below: the generated one can't host auth_request.
          enableNginx = false;

          settings = {
            APP_ENV = "production";
            APP_KEY_FILE = config.sops.secrets."keys/firefly/app-key".path;
            TZ = "Europe/Amsterdam";

            DB_CONNECTION = "pgsql";
            DB_DATABASE = "firefly-iii";
            DB_USERNAME = "firefly-iii";

            # gaia terminates TLS; without this Laravel emits http:// links,
            # breaking even the setup wizard's form action.
            TRUSTED_PROXIES = "**";

            AUTHENTICATION_GUARD = "remote_user_guard";
            AUTHENTICATION_GUARD_HEADER = "REMOTE_USER";
            AUTHENTICATION_GUARD_EMAIL = "REMOTE_USER_EMAIL";

            MAIL_MAILER = "smtp";
            # gaia's Stalwart mesh relay (services/stalwart.nix): no auth or
            # STARTTLS offered, so none configured; hand-synced with gaia.nix
            # relayClients.
            MAIL_HOST = "gaia.nb.lvdar.nl";
            MAIL_PORT = 2525;
            MAIL_FROM = "firefly@lvdar.nl";
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

            # The app's callback URL in Enable Banking's portal must be
            # https://${cfg.importerDomain}/eb-callback.
            ENABLE_BANKING_APP_ID_FILE = config.sops.secrets."keys/firefly/enable-banking-app-id".path;
            ENABLE_BANKING_PRIVATE_KEY_FILE = config.sops.secrets."keys/firefly/enable-banking-private-key".path;

            # Lets the auto-import CLI read config.json from importDir.
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

        # phpfpm sockets are 0660 to their own group; upstream only adds
        # nginx when enableNginx is on. Otherwise "13: Permission denied".
        users.users.nginx.extraGroups = ["firefly-iii" "firefly-iii-data-importer"];

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
          # Personal Access Token created in Firefly's UI after first SSO login.
          "keys/firefly/importer-access-token" = {owner = "firefly-iii-data-importer";};
          "keys/firefly/enable-banking-app-id".owner = "firefly-iii-data-importer";
          "keys/firefly/enable-banking-private-key".owner = "firefly-iii-data-importer";
        };

        # Hand-rolled: services.oauth2-proxy is a singleton already used by
        # microbin.nix. --whitelist-domain is required: --reverse-proxy rejects
        # every redirect when the list is empty.
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
            # OIDC discovery at startup can race kanidm; see microbin.nix.
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

          # Server-level so the PHP location (tryFiles target) is gated too.
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

            # The REST API uses Bearer tokens; the importer got 307-to-login.
            # Must be its own fastcgi location: tryFiles would re-enter the
            # gated "~ \.php$" location.
            "/api/" = phpLocation {
              socket = config.services.phpfpm.pools.firefly-iii.socket;
              scriptFilename = "$document_root/index.php";
              extraConfig = "auth_request off;";
            };

            # Hand-written equivalent of oauth2-proxy-nginx.nix, for :4181.
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
              # No trailing slash: with one, /oauth2/start reaches
              # oauth2-proxy as bare /start and is rejected.
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

        cosmos.services.netbird.client.exposedPorts = [cfg.importerPort];

        # Mesh-only name pointing at this host's NetBird address.
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
