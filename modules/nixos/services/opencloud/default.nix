{
  config,
  lib,
  pkgs,
  ...
}: let
  inherit (lib.options) mkEnableOption;
  inherit (lib.modules) mkIf mkMerge;
  inherit (lib.strings) concatStringsSep;
  inherit (lib.meta) getExe';

  cfg = config.cosmos.services.opencloud;
in {
  options.cosmos.services.opencloud = {
    enable = mkEnableOption "opencloud";
    collabora.enable = mkEnableOption "collabora";
    radicale.enable = mkEnableOption "radicale";
  };

  config = mkMerge [
    (mkIf cfg.enable {
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

        environment = {
          OC_INSECURE = "true";
          OC_LOG_LEVEL = "warn";
          PROXY_TLS = "false";
          PROXY_INSECURE_BACKENDS = "true";
          OC_EXCLUDE_RUN_SERVICES = "idp";
          OC_OIDC_ISSUER = "https://auth.lvdar.nl/oauth2/openid/opencloud";
        };

        settings = {
          proxy = {
            auto_provision_accounts = true;
            auto_provision_claims.groups = "not-a-real-claim";
            oidc.rewrite_well_known = true;
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
              child-src = ["'self'"];
              connect-src = [
                "'self'"
                "blob:"
                "https://auth.lvdar.nl/"
                "https://raw.githubusercontent.com/opencloud-eu/awesome-apps/"
              ];
              default-src = ["'none'"];
              font-src = ["'self'"];
              frame-ancestors = ["'self'" "https://docs.lvdar.nl/"];
              frame-src = [
                "'self'"
                "blob:"
                "https://embed.diagrams.net/"
                "https://docs.lvdar.nl/"
              ];
              img-src = [
                "'self'"
                "data:"
                "blob:"
                "https://docs.lvdar.nl/"
                "https://tile.openstreetmap.org/"
                "https://raw.githubusercontent.com/opencloud-eu/awesome-apps/"
              ];
              manifest-src = ["'self'"];
              media-src = ["'self'"];
              object-src = ["'self'" "blob:"];
              script-src = ["'self'" "'unsafe-inline'"];
              style-src = ["'self'" "'unsafe-inline'"];
            };
          };
          graph.api = {
            graph_assign_default_user_role = false;
            graph_username_match = "none";
          };

          web.web.config.oidc = {
            metadata_url = "https://auth.lvdar.nl/oauth2/openid/opencloud/.well-known/openid-configuration";
            authority = "https://auth.lvdar.nl";
            client_id = "opencloud";
            response_type = "code";
            scope = "openid profile email opencloud_groups";
          };
        };
      };
    })
    (mkIf cfg.collabora.enable {
      services.opencloud = {
        settings.collaboration = {
          app = {
            name = "Collabora";
            product = "Collabora";
            addr = "https://docs.lvdar.nl";
            icon = "https://docs.lvdar.nl/favicon.ico";
            insecure = false;
            proofkeys = {
              disable = false;
              duration = "12h";
            };
            licensecheckenable = false;
          };
          wopi.wopisrc = "https://wopi.lvdar.nl";
        };
        environment = {
          OC_ADD_RUN_SERVICES = "collaboration";
        };
      };

      fonts.packages = with pkgs; [
        atkinson-hyperlegible-next
        corefonts
        gentium
        libertinus
        newcomputermodern
        roboto
        source-sans
      ];

      services.collabora-online = {
        enable = true;
        package = pkgs.collabora-online.overrideAttrs (old: {
          postInstall =
            old.postInstall
            + ''
              ${getExe' pkgs.openssh "ssh-keygen"} -t rsa -N "" -m PEM -f $out/etc/coolwsd/proof_key
            '';
        });

        aliasGroups = [
          {
            host = "wopi.lvdar.nl";
            aliases = [
              "127.0.0.1:9300"
              "127.0.0.1"
              ''127\.0\.0\.1:9300''
              ''127\.0\.0\.1''
            ];
          }
        ];

        settings = {
          user_interface.mode = "tabbed";
          storage.wopi = {
            "@allow" = true;
            alias_groups = {"@mode" = "groups";};
          };
          net.content_security_policy = concatStringsSep " " ["frame-ancestors" "'self'" config.services.opencloud.url];
          server_name = "docs.lvdar.nl";
          ssl = {
            enable = false;
            termination = true;
          };
        };
      };

      systemd.services.coolwsd = {
        serviceConfig = {
          ProtectSystem = "strict";
          ProtectHome = true;
          PrivateTmp = true;
          CapabilityBoundingSet = [
            "CAP_FOWNER"
            "CAP_CHOWN"
            "CAP_SYS_CHROOT"
            "CAP_SYS_ADMIN"
            "CAP_MKNOD"
          ];
        };
      };
    })
  ];
}
