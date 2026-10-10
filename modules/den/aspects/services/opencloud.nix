# services.opencloud — file sync and share, with Collabora for editing in the
# browser. WOPI needs three domains: cloud (OpenCloud), docs (Collabora, framed
# by the browser), wopi (collaboration service, fetched server to server).
# Diff the CSP against opencloud-compose's csp.yaml on upgrade.
{...}: {
  den.aspects.services.opencloud.nixos = {
    config,
    lib,
    pkgs,
    ...
  }: let
    inherit (lib.options) mkOption mkEnableOption;
    inherit (lib.types) path port str;
    inherit (lib.modules) mkIf;

    cfg = config.cosmos.services.opencloud;

    inherit (config.cosmos.services.opencloud) domain docsDomain wopiDomain;
  in {
    options.cosmos.services.opencloud = {
      domain = mkOption {
        type = str;
        default = "cloud.lvdar.nl";
      };
      docsDomain = mkOption {
        type = str;
        default = "docs.lvdar.nl";
        description = "Where Collabora answers the browser.";
      };
      wopiDomain = mkOption {
        type = str;
        default = "wopi.lvdar.nl";
        description = ''
          Where Collabora fetches documents from. Reached server-to-server, so
          it has to resolve and answer for Collabora, not just for a browser.
        '';
      };

      dataDir = mkOption {
        type = path;
        default = "/var/lib/opencloud";
        description = ''
          Everything OpenCloud owns: uploaded blobs, the search index, the user
          database. OC_BASE_DATA_PATH points here, so it is one directory
          rather than a split between state and data.
        '';
      };

      port = mkOption {
        type = port;
        default = 9200;
      };
      wopiPort = mkOption {
        type = port;
        default = 9300;
      };
      docsPort = mkOption {
        type = port;
        default = 9980;
      };

      collabora.enable = mkEnableOption "Collabora Online" // {default = true;};

      tika.enable =
        mkEnableOption "full-text search inside documents, via Apache Tika"
        // {default = true;};

      smtp = {
        enable = mkEnableOption ''
          outgoing mail, so sharing with someone actually tells them.

          Off until `keys/opencloud/smtp` exists in nix-secrets: the sops
          secret is referenced only when this is on, so that a host without it
          still evaluates and deploys
        '';
        host = mkOption {
          type = str;
          default = "";
        };
        port = mkOption {
          type = port;
          default = 587;
        };
        sender = mkOption {
          type = str;
          default = "OpenCloud <cloud@lvdar.nl>";
        };
        username = mkOption {
          type = str;
          default = "";
        };
      };
    };

    config = {
      cosmos.system.impermanence.persist = {
        # JWT key, machine-auth key, service credentials: lose this and
        # everything under dataDir is orphaned.
        files = ["/etc/opencloud/opencloud.yaml"];
        # Tika's state is deliberately not persisted: DynamicUser fights the mount.
        directories = [
          {
            directory = "/var/lib/cool";
            user = "cool";
            group = "cool";
            mode = "0750";
          }
        ];
      };

      services.opencloud = {
        enable = true;
        url = "https://${domain}";
        inherit (cfg) port;
        stateDir = cfg.dataDir;

        address = "0.0.0.0";

        environmentFile =
          lib.mkIf cfg.smtp.enable
          config.sops.secrets."keys/opencloud/smtp".path;

        environment =
          {
            OC_INSECURE = "true";
            OC_LOG_LEVEL = "warn";
            PROXY_TLS = "false";
            PROXY_INSECURE_BACKENDS = "true";
            # The built-in `idp` would otherwise claim the OIDC routes.
            OC_EXCLUDE_RUN_SERVICES = "idp";
            OC_OIDC_ISSUER = "https://auth.lvdar.nl/oauth2/openid/opencloud";
            # Set globally: OpenCloud defaults it to "web" in several places,
            # and any one falling back makes kanidm answer `invalid_client_id`.
            OC_OIDC_CLIENT_ID = "opencloud";
          }
          // lib.optionalAttrs cfg.tika.enable {
            SEARCH_EXTRACTOR_TYPE = "tika";
            SEARCH_EXTRACTOR_TIKA_TIKA_URL = "http://127.0.0.1:${toString config.services.tika.port}";
          }
          // lib.optionalAttrs cfg.smtp.enable {
            NOTIFICATIONS_SMTP_HOST = cfg.smtp.host;
            NOTIFICATIONS_SMTP_PORT = toString cfg.smtp.port;
            NOTIFICATIONS_SMTP_SENDER = cfg.smtp.sender;
            NOTIFICATIONS_SMTP_USERNAME = cfg.smtp.username;
            NOTIFICATIONS_SMTP_AUTHENTICATION = "login";
            NOTIFICATIONS_SMTP_ENCRYPTION = "starttls";
            # NOTIFICATIONS_SMTP_PASSWORD comes via environmentFile: this
            # attrset lands in the world-readable store.
          }
          // lib.optionalAttrs cfg.collabora.enable {
            OC_ADD_RUN_SERVICES = "collaboration";
            # Not loopback: Collabora reaches it back through the edge.
            COLLABORATION_HTTP_ADDR = "0.0.0.0:${toString cfg.wopiPort}";
          };

        settings = {
          proxy = {
            auto_provision_accounts = true;
            # A real claim would create groups that fight the role mapper.
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

          # docs must frame and be framed by cloud, or the editor is blank.
          csp.directives = {
            child-src = ["'self'"];
            connect-src = [
              "'self'"
              "blob:"
              "https://auth.lvdar.nl/"
              "https://raw.githubusercontent.com/opencloud-eu/awesome-apps/"
              # Map tiles are fetched over XHR, not only displayed.
              "https://tile.openstreetmap.org/"
            ];
            default-src = ["'none'"];
            font-src = ["'self'"];
            frame-ancestors = ["'self'" "https://${docsDomain}/"];
            frame-src = [
              "'self'"
              "blob:"
              "https://embed.diagrams.net/"
              "https://${docsDomain}/"
              # Silent token renewal runs in a hidden iframe.
              "https://auth.lvdar.nl/"
            ];
            img-src = [
              "'self'"
              "data:"
              "blob:"
              "https://${docsDomain}/"
              "https://tile.openstreetmap.org/"
              "https://raw.githubusercontent.com/opencloud-eu/awesome-apps/"
            ];
            manifest-src = ["'self'"];
            media-src = ["'self'"];

            # Without it Firefox falls back to default-src 'none' for worker chunks.
            worker-src = ["'self'" "blob:"];

            # NO form-action: it does not inherit default-src, and WOPI POSTs a
            # form to Collabora — restricting it to 'self' broke the editor.
            object-src = ["'self'" "blob:"];
            script-src = ["'self'" "'unsafe-inline'" "https://auth.lvdar.nl/"];
            style-src = ["'self'" "'unsafe-inline'"];
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

          collaboration = mkIf cfg.collabora.enable {
            app = {
              name = "Collabora";
              product = "Collabora";
              addr = "https://${docsDomain}";
              icon = "https://${docsDomain}/favicon.ico";
              insecure = false;
              licensecheckenable = false;

              # Collabora 25.04 cannot find a proof key with a store config, and
              # generating one put a private key in the store. Both ends are
              # on this host behind an authenticating edge.
              proofkeys.disable = true;
            };
            wopi.wopisrc = "https://${wopiDomain}";
          };
        };
      };

      # Without network-online, `collaboration` cannot resolve docs.lvdar.nl at
      # boot and the unit fails and alerts before restarting (as services/ddns.nix).
      systemd.services.opencloud = {
        wants = ["network-online.target"];
        after = ["network-online.target" "nss-lookup.target"];
      };

      # Go's route lookup needs AF_NETLINK; without it the collaboration startup
      # probe never passes and every document open fails.
      systemd.services.opencloud.serviceConfig.RestrictAddressFamilies = lib.mkForce [
        "AF_UNIX"
        "AF_INET"
        "AF_INET6"
        "AF_NETLINK"
      ];

      # Seeded on the persistent side: the module's init unit races the /etc
      # bind mount under ProtectSystem=strict and fails with EROFS.
      systemd.services.opencloud-seed-config = {
        description = "Seed OpenCloud's machine config on the persistent volume";
        wantedBy = ["multi-user.target"];
        # After the bind mount: ordering before local-fs.target makes a cycle
        # that systemd breaks by dropping this job.
        after = ["persist-persist-etc-opencloud-opencloud.yaml.service"];
        before = [
          "opencloud-init-config.service"
          "opencloud.service"
        ];

        environment = {
          OC_BASE_DATA_PATH = cfg.dataDir;
          OC_URL = "https://${domain}";
        };

        path = [config.services.opencloud.package];

        serviceConfig = {
          Type = "oneshot";
          RemainAfterExit = true;
        };

        script = let
          target = "/etc/opencloud/opencloud.yaml";
        in ''
          # Impermanence creates the file empty when its source is missing, so
          # "exists" is not the question — "has anything in it" is. The module's
          # own init only checks the former, which is how an empty file used to
          # get it skipped and left the server without a jwt_secret.
          if [ -s ${target} ]; then
            exit 0
          fi

          work="$(mktemp -d)"
          trap 'rm -rf "$work"' EXIT

          # Quietly: it prints the generated local admin password, and a
          # password in the journal outlives every reason it was shown. That
          # account is unused anyway — logins come from kanidm — and the value
          # is in the config file if it is ever wanted.
          opencloud init --insecure true --config-path "$work" >/dev/null

          # Written into the existing file rather than moved over it: the path
          # is a bind mount, and replacing it would detach the mount and leave
          # the real copy on /persist untouched.
          cat "$work/opencloud.yaml" > ${target}
          chown ${config.services.opencloud.user}:${config.services.opencloud.group} ${target}
          chmod 0600 ${target}
        '';
      };

      sops.secrets = lib.mkIf cfg.smtp.enable {
        "keys/opencloud/smtp".owner = config.services.opencloud.user;
      };

      # Loopback-only: a JVM that will parse anything it is handed.
      services.tika = mkIf cfg.tika.enable {
        enable = true;
        listenAddress = "127.0.0.1";
        enableOcr = true;
      };

      # Rendered server-side; missing fonts are silently substituted.
      fonts.packages = mkIf cfg.collabora.enable (with pkgs; [
        atkinson-hyperlegible-next
        corefonts
        gentium
        libertinus
        newcomputermodern
        roboto
        source-sans
      ]);

      services.collabora-online = mkIf cfg.collabora.enable {
        enable = true;
        port = cfg.docsPort;

        aliasGroups = [
          {
            host = "https://${wopiDomain}";
            aliases = ["https://${wopiDomain}"];
          }
        ];

        settings = {
          server_name = docsDomain;
          user_interface.mode = "tabbed";

          storage.wopi = {
            "@allow" = true;
            alias_groups = {"@mode" = "groups";};
          };

          # Counterpart of OpenCloud's frame-ancestors above.
          net.content_security_policy =
            lib.concatStringsSep " " ["frame-ancestors" "'self'" "https://${domain}"];

          # Without `termination`, coolwsd emits http:// URLs blocked as mixed content.
          ssl = {
            enable = false;
            termination = true;
          };
        };
      };

      systemd.services.coolwsd.serviceConfig = mkIf cfg.collabora.enable {
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
  };
}
