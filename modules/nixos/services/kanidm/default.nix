{
  config,
  lib,
  pkgs,
  ...
}: let
  inherit (lib.options) mkEnableOption;
  inherit (lib.modules) mkIf;

  cfg = config.cosmos.services.kanidm;
in {
  options.cosmos.services.kanidm = {
    enable = mkEnableOption "kanidm";
  };

  config = mkIf cfg.enable {
    cosmos.system.impermanence.persist.directories = ["/var/lib/kanidm"];

    sops.secrets = {
      "keys/kanidm/admin-password" = {
        owner = "kanidm";
      };
      "keys/kanidm/idm-admin-password" = {
        owner = "kanidm";
      };
      "keys/kanidm/oauth-cosmos-client-secret" = {
        owner = "kanidm";
        group = "vouch-kanidm";
        mode = "0640";
      };
      "keys/vouch/jwt" = {
        owner = "vouch-proxy";
      };
    };

    users.users = {
      vouch-proxy = {
        isSystemUser = true;
        group = "vouch-proxy";
        extraGroups = ["vouch-kanidm"];
      };
      kanidm.extraGroups = ["acme" "vouch-kanidm"];
    };

    users.groups = {
      vouch-kanidm = {};
      vouch-proxy = {};
    };

    services.kanidm = {
      package = pkgs.kanidmWithSecretProvisioning_1_7;
      enableServer = true;
      serverSettings = {
        domain = "lvdar.nl";
        origin = "https://auth.lvdar.nl";
        tls_chain = "/var/lib/acme/lvdar.nl/fullchain.pem";
        tls_key = "/var/lib/acme/lvdar.nl/key.pem";
        trust_x_forward_for = true;
      };

      provision = {
        enable = true;
        adminPasswordFile = config.sops.secrets."keys/kanidm/admin-password".path;
        idmAdminPasswordFile = config.sops.secrets."keys/kanidm/idm-admin-password".path;

        persons = {
          lvdar = {
            displayName = "lvdar";
            mailAddresses = ["lars@lvdar.nl"];
          };
        };

        groups = {
          users = {
            members = ["lvdar"];
          };
        };

        systems.oauth2 = {
          cosmos = {
            displayName = "Cosmos Auth";
            basicSecretFile = config.sops.secrets."keys/kanidm/oauth-cosmos-client-secret".path;
            originUrl = "https://login.lvdar.nl/auth";
            originLanding = "https://login.lvdar.nl/auth";
            scopeMaps = {
              users = ["login" "openid" "email"];
            };
          };
        };
      };
    };

    systemd.services.vouch-proxy = let
      vouchConfig = {
        vouch = {
          logLevel = "debug";
          listen = "[::1]";
          port = 30746;

          # TODO: this allows everybody that can authenticate to kanidm, so no
          # further scoping possible atm.
          allowAllUsers = true;
          cookie.domain = "lvdar.nl";
          jwt.secret = "@JWT_SECRET@";
        };
        oauth = let
          kanidmOrigin = config.services.kanidm.serverSettings.origin;
        in rec {
          provider = "oidc";
          client_id = "cosmos";
          client_secret = "@CLIENT_SECRET@";
          auth_url = "${kanidmOrigin}/ui/oauth2";
          token_url = "${kanidmOrigin}/oauth2/token";
          user_info_url = "${kanidmOrigin}/oauth2/openid/${client_id}/userinfo";
          scopes = ["login" "openid" "email"];
          callback_url = "https://login.lvdar.nl/auth";
          code_challenge_method = "S256";
        };
      };
    in {
      description = "Vouch-proxy";
      after = ["network.target"];
      wantedBy = ["multi-user.target"];
      serviceConfig = {
        ExecStart = let
          secrets = {
            JWT_SECRET = config.sops.secrets."keys/vouch/jwt".path;
            CLIENT_SECRET = config.sops.secrets."keys/kanidm/oauth-cosmos-client-secret".path;
          };
          vouchConfigTemplate = "${(pkgs.formats.yaml {}).generate "config.yml" vouchConfig}";
          vouchConfigFinal = "/var/lib/vouch-proxy/config.yml";
          script = pkgs.writeShellScript "run-vouch-proxy" ''
            set -euo pipefail

            cp ${vouchConfigTemplate} ${vouchConfigFinal}

            ${
              lib.strings.concatMapAttrsStringSep
              "\n"
              (name: value: ''
                sed -i "s|@${name}@|$(cat ${value} | sed 's/[&/\]/\\&/g')|g" ${vouchConfigFinal}
              '')
              secrets
            }

            ${pkgs.vouch-proxy}/bin/vouch-proxy -config ${vouchConfigFinal}
          '';
        in "${script}";
        Restart = "on-failure";
        RestartSec = 5;
        WorkingDirectory = "/var/lib/vouch-proxy";
        StateDirectory = "vouch-proxy";
        RuntimeDirectory = "vouch-proxy";
        User = "vouch-proxy";
        Group = "vouch-proxy";
        StartLimitBurst = 3;
      };
    };

    services.nginx.virtualHosts = {
      "login.lvdar.nl" = {
        forceSSL = true;
        enableACME = false;
        sslCertificate = "/var/lib/acme/lvdar.nl/fullchain.pem";
        sslCertificateKey = "/var/lib/acme/lvdar.nl/key.pem";

        locations."/" = {
          proxyPass = "http://[::1]:30746";
        };
      };

      "auth.lvdar.nl" = {
        forceSSL = true;
        enableACME = false;
        sslCertificate = "/var/lib/acme/lvdar.nl/fullchain.pem";
        sslCertificateKey = "/var/lib/acme/lvdar.nl/key.pem";

        locations."/" = {
          proxyPass = "https://127.0.0.1:8443";
        };
      };
    };
  };
}
