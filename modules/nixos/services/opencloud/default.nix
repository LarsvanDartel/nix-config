{
  config,
  lib,
  ...
}: let
  inherit (lib.options) mkEnableOption;
  inherit (lib.modules) mkIf;

  cfg = config.cosmos.services.opencloud;
in {
  options.cosmos.services.opencloud = {
    enable = mkEnableOption "opencloud";
  };

  config = mkIf cfg.enable {
    cosmos.system.impermanence.persist = {
      files = ["/etc/opencloud/opencloud.yaml"];
      directories = [
        {
          directory = "/var/lib/opencloud";
          user = "opencloud";
          group = "opencloud";
          mode = "0750";
        }
      ];
    };

    services.opencloud = {
      enable = true;
      url = "https://cloud.lvdar.nl";
      address = "0.0.0.0";
      settings = {
        api = {
          graph_assign_default_user_role = true;
          graph_username_match = "none";
        };
        proxy = {
          auto_provision_accounts = true;
          oidc.rewrite_well_known = true;
          oidc.access_token_verify_method = "none";
          role_assignment = {
            driver = "oidc";
            oidc_role_mapper = {
              role_claim = "opencloud_groups";
              role_mapping = [
                {
                  role_name = "admin";
                  claim_value = "admin";
                }
                {
                  role_name = "user";
                  claim_value = "user";
                }
                {
                  role_name = "guest";
                  claim_value = "guest";
                }
              ];
            };
          };
          csp_config_file_location = "/etc/opencloud/csp.yaml";
        };
        csp = {
          directives = {
            connect-src = [
              "https://cloud.lvdar.nl/"
              "https://auth.lvdar.nl/"
            ];
            frame-src = [
              "https://cloud.lvdar.nl/"
              "https://auth.lvdar.nl/"
            ];
            script-src = ["'self'" "'unsafe-inline'" "'unsafe-eval'"];
          };
        };
        web.web.config.oidc = {
          metadata_url = "https://auth.lvdar.nl/oauth2/openid/opencloud/.well-known/openid-configuration";
          authority = "https://auth.lvdar.nl";
          client_id = "opencloud";
          response_type = "code";
          scope = "openid profile email opencloud_groups";
        };
      };

      environment = {
        OC_INSECURE = "false";
        PROXY_TLS = "false";
        PROXY_INSECURE_BACKENDS = "true";
        OC_EXCLUDE_RUN_SERVICES = "idp";
        OC_OIDC_ISSUER = "https://auth.lvdar.nl/oauth2/openid/opencloud";

        # Auto-provision accounts from OIDC
        PROXY_AUTOPROVISION_ACCOUNTS = "true";
        PROXY_AUTOPROVISION_CLAIM_USERNAME = "preferred_username";
        PROXY_AUTOPROVISION_CLAIM_EMAIL = "email";
        PROXY_AUTOPROVISION_CLAIM_DISPLAYNAME = "name";
        PROXY_AUTOPROVISION_CLAIM_GROUPS = "opencloud_groups";
        PROXY_USER_OIDC_CLAIM = "preferred_username";
        PROXY_USER_CS3_CLAIM = "username";
        GRAPH_USERNAME_MATCH = "none";
      };
    };
  };
}
