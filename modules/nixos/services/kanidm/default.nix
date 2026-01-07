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
    };

    users.users = {
      kanidm.extraGroups = ["acme"];
    };

    services.kanidm = {
      package = pkgs.kanidmWithSecretProvisioning_1_8;
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
      };
    };

    services.nginx.virtualHosts = {
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
