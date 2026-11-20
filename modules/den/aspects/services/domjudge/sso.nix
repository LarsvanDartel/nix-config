# services.domjudge.sso — judge.lvdar.nl behind kanidm via oauth2-proxy, nginx auth_request and Remote-User.
{
  den,
  inputs,
  ...
}: let
  inherit (import ./_lib.nix) containerPort;

  domain = "judge.lvdar.nl";
  defaultPort = 8092;
  # firefly's oauth2-proxy holds 4181.
  oauthPort = 4182;
in {
  den.aspects.services.domjudge.sso = {
    includes = with den.aspects.services; [domjudge nginx netbird.client];

    netbird-service = {host, ...}: {
      judge = {
        # Ungated: kanidm SSO is a full login, and /api/ falls back to the domserver's basic auth.
        bearerAuth.enable = false;
        targets = [
          {
            peer = host.name;
            port = defaultPort;
          }
        ];
      };
    };

    kanidm-provision = {
      groups.domjudge-users = {
        overwriteMembers = false;
        members = ["lvdar"];
      };

      oauth2.domjudge = {
        displayName = "DOMjudge";
        basicSecret = "keys/domjudge/oauth-client-secret";
        originUrl = "https://${domain}/oauth2/callback";
        originLanding = "https://${domain}";
        scopeMaps.domjudge-users = ["openid" "profile" "email"];
        # preferred_username is the DOMjudge username: `lvdar`, not the SPN.
        preferShortUsername = true;
      };
    };

    nixos = {
      config,
      lib,
      pkgs,
      ...
    }: let
      inherit (lib.options) mkOption;
      inherit (lib.types) port;

      cfg = config.cosmos.services.domjudge;
    in {
      options.cosmos.services.domjudge.port = mkOption {
        type = port;
        default = defaultPort;
      };

      config = {
        cosmos.services.netbird.client.exposedPorts = [cfg.port];

        sops.secrets = {
          "keys/domjudge/cookie-secret" = {};
          # Shared with kanidm's host (services/kanidm.nix), hence hosts/common.
          "keys/domjudge/oauth-client-secret".sopsFile =
            builtins.toString inputs.nix-secrets + "/hosts/common/secrets.yaml";
        };

        # Hand-rolled like firefly.nix's: services.oauth2-proxy is a singleton.
        systemd.services.oauth2-proxy-domjudge = {
          description = "oauth2-proxy for DOMjudge";
          after = ["network.target" "kanidm.service"];
          wantedBy = ["multi-user.target"];
          serviceConfig = {
            DynamicUser = true;
            LoadCredential = [
              "client-secret:${config.sops.secrets."keys/domjudge/oauth-client-secret".path}"
              "cookie-secret:${config.sops.secrets."keys/domjudge/cookie-secret".path}"
            ];
            # --oidc-email-claim: kanidm persons without a mail address
            # otherwise fail the callback with a 500.
            ExecStart = ''
              ${lib.getExe pkgs.oauth2-proxy} \
                --http-address=127.0.0.1:${toString oauthPort} \
                --provider=oidc \
                --oidc-issuer-url=https://auth.lvdar.nl/oauth2/openid/domjudge \
                --client-id=domjudge \
                --client-secret-file=%d/client-secret \
                --cookie-secret-file=%d/cookie-secret \
                --redirect-url=https://${domain}/oauth2/callback \
                --upstream=static://202 \
                --oidc-email-claim=preferred_username \
                --email-domain=* \
                --whitelist-domain=${domain} \
                --set-xauthrequest \
                --reverse-proxy \
                --trusted-proxy-ip=127.0.0.1/32 \
                --trusted-proxy-ip=::1/128 \
                --code-challenge-method=S256 \
                --skip-provider-button
            '';
            Restart = "on-failure";
            RestartSec = "10s";
          };
          unitConfig = {
            StartLimitIntervalSec = "15min";
            StartLimitBurst = 60;
          };
        };

        services.nginx.virtualHosts.${domain} = {
          listen = [
            {
              addr = "0.0.0.0";
              port = cfg.port;
            }
          ];

          extraConfig = ''
            ${config.cosmos.services.netbird.client.proxyRealIp}
            auth_request /oauth2/auth;
            error_page 401 = @redirectToAuth2ProxyLogin;
            auth_request_set $auth_user $upstream_http_x_auth_request_preferred_username;
            client_max_body_size 256m;
          '';

          locations = {
            "/" = {
              proxyPass = "http://127.0.0.1:${toString containerPort}";
              # The recommended include sends X-Forwarded-Proto $scheme (http);
              # a second proxy_set_header would duplicate it.
              recommendedProxySettings = false;
              # X-Forwarded-Proto https makes the container's nginx set
              # HTTPS=on. Setting Remote-User replaces any client-sent value.
              extraConfig = ''
                proxy_set_header Host $host;
                proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
                proxy_set_header X-Forwarded-Proto https;
                proxy_set_header Remote-User $auth_user;
                proxy_read_timeout 600s;
              '';
            };

            # The API uses HTTP basic auth (submit CLI): clear Remote-User so the domserver falls
            # back to it, and pass 401s through instead of redirecting to the oauth2 login.
            "^~ /api/" = {
              proxyPass = "http://127.0.0.1:${toString containerPort}";
              recommendedProxySettings = false;
              extraConfig = ''
                auth_request off;
                error_page 401 = @api401;
                proxy_set_header Host $host;
                proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
                proxy_set_header X-Forwarded-Proto https;
                proxy_set_header Remote-User "";
                proxy_read_timeout 600s;
              '';
            };

            "= /oauth2/auth" = {
              proxyPass = "http://127.0.0.1:${toString oauthPort}/oauth2/auth";
              extraConfig = ''
                auth_request off;
                proxy_set_header X-Scheme https;
                proxy_set_header Content-Length "";
                proxy_pass_request_body off;
              '';
            };

            "/oauth2/" = {
              # No trailing slash: /oauth2/start must reach oauth2-proxy whole.
              proxyPass = "http://127.0.0.1:${toString oauthPort}";
              extraConfig = ''
                auth_request off;
                proxy_set_header X-Scheme https;
                proxy_set_header X-Auth-Request-Redirect https://$host$request_uri;
              '';
            };

            "@redirectToAuth2ProxyLogin" = {
              return = "307 https://${domain}/oauth2/start?rd=https://$host$request_uri";
              extraConfig = "auth_request off;";
            };

            # Entered on a proxied 401 under /api/: stop the inherited
            # oauth2 redirect and answer with a bare 401 the CLI understands.
            "@api401" = {
              extraConfig = ''
                auth_request off;
                return 401;
              '';
            };
          };
        };
      };
    };
  };
}
