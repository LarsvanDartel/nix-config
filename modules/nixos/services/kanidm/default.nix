{
  config,
  lib,
  pkgs,
  ...
}: let
  inherit (lib.options) mkEnableOption mkOption;
  inherit (lib.types) bool;
  inherit (lib.modules) mkIf;

  cfg = config.cosmos.services.kanidm;
in {
  options.cosmos.services.kanidm = {
    enable = mkEnableOption "kanidm";
    expose = mkOption {
      type = bool;
      default = false;
    };
  };

  config = mkIf cfg.enable {
    cosmos.system.impermanence.persist.directories = [
      {
        directory = "/var/lib/kanidm";
        user = "kanidm";
        group = "kadidm";
        mode = "0750";
      }
    ];

    sops.secrets = {
      "keys/kanidm/admin-password" = {
        owner = "kanidm";
      };
      "keys/kanidm/idm-admin-password" = {
        owner = "kanidm";
      };
      "keys/pangolin/oauth-client-secret" = {
        owner = "kanidm";
      };
      "keys/immich/oauth-client-secret" = {
        owner = "kanidm";
      };
    };

    users.users = {
      kanidm.extraGroups = ["acme"];
    };

    services.kanidm = {
      package = pkgs.kanidmWithSecretProvisioning_1_8;
      server = {
        enable = true;
        settings = {
          domain = "lvdar.nl";
          origin = "https://auth.lvdar.nl";
          tls_chain = "/var/lib/acme/lvdar.nl/fullchain.pem";
          tls_key = "/var/lib/acme/lvdar.nl/key.pem";
          http_client_address_info.x-forward-for = ["127.0.0.1"];
        };
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
          pangolin-users = {
            overwriteMembers = false;
            members = ["lvdar"];
          };
          pangolin-admin = {
            members = ["lvdar"];
          };
          immich-users = {
            overwriteMembers = false;
            members = ["lvdar"];
          };
          immich-admin = {
            members = ["lvdar"];
          };
          opencloud-users = {
            overwriteMembers = false;
            members = ["lvdar"];
          };
          opencloud-admin = {
            members = ["lvdar"];
          };
        };
        systems.oauth2 = {
          pangolin = {
            displayName = "Pangolin";
            basicSecretFile = config.sops.secrets."keys/pangolin/oauth-client-secret".path;
            originUrl = "https://pangolin.lvdar.nl/auth/idp/1/oidc/callback";
            originLanding = "https://pangolin.lvdar.nl";
            scopeMaps = {
              pangolin-users = ["openid" "profile" "email"];
            };
            claimMaps = {
              groups = {
                joinType = "array";
                valuesByGroup = {
                  pangolin-users = ["cosmos"];
                  pangolin-admin = ["admin"];
                };
              };
            };
          };
          opencloud = {
            displayName = "Opencloud";
            public = true;
            originUrl = [
              "https://cloud.lvdar.nl/"
              "https://cloud.lvdar.nl/oidc-callback.html"
              "https://cloud.lvdar.nl/oidc-silent-redirect.html"
            ];
            originLanding = "https://cloud.lvdar.nl";
            scopeMaps = {
              opencloud-users = ["openid" "profile" "email" "opencloud_groups"];
            };
            claimMaps = {
              opencloud_groups = {
                joinType = "array";
                valuesByGroup = {
                  opencloud-users = ["user"];
                  opencloud-admin = ["admin"];
                };
              };
            };
          };
          immich = {
            displayName = "Immich";
            originUrl = [
              "app.immich:///oauth-callback"
              "https://immich.lvdar.nl/auth/login"
              "https://immich.lvdar.nl/user-settings"
            ];
            originLanding = "https://immich.lvdar.nl";
            scopeMaps = {
              immich-users = ["openid" "profile" "email"];
            };
            claimMaps = {
              immich_groups = {
                joinType = "array";
                valuesByGroup = {
                  immich-admin = ["admin"];
                };
              };
            };
          };
        };
      };
    };

    services.nginx.virtualHosts = mkIf cfg.expose {
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
