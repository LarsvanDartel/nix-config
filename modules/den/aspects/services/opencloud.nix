# services.opencloud — file sync and share, with Collabora for editing in the
# browser. Three domains, because that is what the WOPI protocol needs:
#
#   cloud   OpenCloud itself, and the only one a person types
#   docs    Collabora, loaded into an iframe by the browser
#   wopi    OpenCloud's `collaboration` service, which Collabora fetches the
#           document from — server to server, not through the browser
#
# All three are published, and none is gated at the edge: OpenCloud runs its
# own OIDC against kanidm, and the other two are machine-to-machine legs that
# cannot answer an interactive login.
#
# This replaces an earlier attempt where OpenCloud worked but editing did not.
# The difference is proof keys — see the collaboration block below.
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
    };

    config = {
      cosmos.system.impermanence.persist = {
        # The machine's own secrets — JWT signing key, machine-auth key, the
        # per-service account credentials, LDAP bind passwords. Generated once
        # and then load-bearing: lose this and every account and blob under
        # dataDir is orphaned.
        files = ["/etc/opencloud/opencloud.yaml"];
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

        # Reached from the mesh rather than a local vhost, like every other
        # published service on this host.
        address = "0.0.0.0";

        environment =
          {
            OC_INSECURE = "true";
            OC_LOG_LEVEL = "warn";
            # TLS terminates at the edge; the mesh hop behind it is plain HTTP.
            PROXY_TLS = "false";
            PROXY_INSECURE_BACKENDS = "true";
            # kanidm is the IdP, so OpenCloud's built-in one stays out of the
            # way. Its own `idp` service would otherwise claim the OIDC routes.
            OC_EXCLUDE_RUN_SERVICES = "idp";
            OC_OIDC_ISSUER = "https://auth.lvdar.nl/oauth2/openid/opencloud";
            # Set globally, not just under `web`, because OpenCloud defaults it
            # to "web" in more than one place and only one of them has to fall
            # back for kanidm to answer `invalid_client_id` — the client is
            # registered as `opencloud`, which is also the name kanidm builds
            # the issuer path from, so the two cannot be allowed to disagree.
            OC_OIDC_CLIENT_ID = "opencloud";
          }
          // lib.optionalAttrs cfg.collabora.enable {
            OC_ADD_RUN_SERVICES = "collaboration";
            # The collaboration service defaults to loopback, which is right
            # only when Collabora is on the same host *and* talking to it
            # directly. It goes out to wopiDomain and comes back through the
            # edge, so it has to answer on the mesh interface too.
            COLLABORATION_HTTP_ADDR = "0.0.0.0:${toString cfg.wopiPort}";
          };

        settings = {
          proxy = {
            auto_provision_accounts = true;
            # Roles come from the claim below, so the group claim must not also
            # drive provisioning — a real claim name here would have OpenCloud
            # create a group per value and fight the role mapper for them.
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

          # OpenCloud ships a default CSP that knows nothing about Collabora.
          # The editor is an iframe, so `docs` has to be allowed to be framed
          # by `cloud` and to frame it back — miss either and the editor loads
          # as a blank rectangle with the reason only in the browser console.
          csp.directives = {
            child-src = ["'self'"];
            connect-src = [
              "'self'"
              "blob:"
              "https://auth.lvdar.nl/"
              "https://raw.githubusercontent.com/opencloud-eu/awesome-apps/"
            ];
            default-src = ["'none'"];
            font-src = ["'self'"];
            frame-ancestors = ["'self'" "https://${docsDomain}/"];
            frame-src = [
              "'self'"
              "blob:"
              "https://embed.diagrams.net/"
              "https://${docsDomain}/"
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
            # Both were absent, so they fell through to `default-src 'none'`
            # and Firefox blocked same-origin resources: the module chunks the
            # web UI loads in a worker, and the navigation to /web-oidc-callback
            # at the end of a login.
            worker-src = ["'self'" "blob:"];
            form-action = ["'self'"];
            media-src = ["'self'"];
            object-src = ["'self'" "blob:"];
            script-src = ["'self'" "'unsafe-inline'"];
            style-src = ["'self'" "'unsafe-inline'"];
          };

          graph.api = {
            # Roles are the OIDC claim's business, not a default handed out at
            # first login.
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

              # Proof keys are Collabora signing its WOPI requests so the host
              # can tell them from a forgery. Collabora 25.04 has no switch for
              # them and keeps the key at /etc/coolwsd/proof_key, which does not
              # exist when the config comes from the store — the previous
              # attempt worked around that by generating one into the package at
              # build time, which put a private key in the world-readable store
              # and still left the two ends disagreeing. Editing failed there.
              #
              # Verification off instead. What it protects against is something
              # impersonating Collabora to the WOPI host, and both ends of this
              # hop are services on one machine talking over the mesh, behind an
              # edge that already authenticates.
              proofkeys.disable = true;
            };
            wopi.wopisrc = "https://${wopiDomain}";
          };
        };
      };

      # The collaboration service will not start without netlink. Its startup
      # health check is a "web reachability" probe, and Go's route lookup opens
      # an AF_NETLINK socket to enumerate interfaces; nixpkgs' sandbox allows
      # only AF_UNIX, AF_INET and AF_INET6, so the call fails with "netlinkrib:
      # address family not supported by protocol". The check then never passes,
      # the service never registers, and every attempt to open a document ends
      # at `GetAppProviderClient: eu.opencloud.api.collaboration: service not
      # found` — which the browser renders as "Error contacting the requested
      # application" over a black screen.
      #
      # This, not proof keys, is why editing never worked.
      systemd.services.opencloud.serviceConfig.RestrictAddressFamilies = lib.mkForce [
        "AF_UNIX"
        "AF_INET"
        "AF_INET6"
        "AF_NETLINK"
      ];

      # OpenCloud's own provisioning writes that file into /etc/opencloud, and
      # here it cannot: the path is an impermanence bind mount, and the unit
      # doing the writing runs under ProtectSystem=strict, so it races the mount
      # and lands on a read-only /etc — `opencloud init` fails with EROFS and
      # the server then refuses to start over a missing jwt_secret.
      #
      # Generate it on the persistent side instead, before anything mounts it.
      # The module's own init unit still runs and still checks for the file; by
      # then it exists and is non-empty, so it does nothing. Seeding rather than
      # declaring keeps every one of those secrets out of the store.
      systemd.services.opencloud-seed-config = {
        description = "Seed OpenCloud's machine config on the persistent volume";
        wantedBy = ["multi-user.target"];
        # After the bind mount, not before it: that mount belongs to
        # local-fs.target, so ordering ahead of it puts this unit before
        # sysinit.target while still depending on it, and systemd breaks the
        # cycle by dropping the job. Writing through the mount is fine — it
        # lands on /persist, and this unit carries none of the sandboxing that
        # made OpenCloud's own attempt fail.
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

      # Collabora renders documents server-side, so the fonts a document asks
      # for have to exist here or it silently substitutes.
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

        # Collabora refuses to serve a document whose WOPI host it does not
        # recognise. The group's first entry is the name it is asked for; the
        # aliases are the forms the same host can arrive as.
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

          # Who may put the editor in an iframe. The counterpart of
          # frame-ancestors above, and just as fatal to get wrong.
          net.content_security_policy =
            lib.concatStringsSep " " ["frame-ancestors" "'self'" "https://${domain}"];

          # TLS ends at the edge, so coolwsd speaks plain HTTP and is told the
          # world still sees it as HTTPS — without `termination` it generates
          # http:// URLs and the browser blocks them as mixed content.
          ssl = {
            enable = false;
            termination = true;
          };
        };
      };

      # coolwsd builds a chroot per document to sandbox the conversion, which
      # needs rather more than a web service usually would.
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
