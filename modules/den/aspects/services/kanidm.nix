# services.kanidm — identity provider (OIDC for pangolin/immich/opencloud/traccar).
{...}: {
  den.aspects.services.kanidm.nixos = {
    config,
    lib,
    pkgs,
    ...
  }: let
    inherit (lib.options) mkOption;
    inherit (lib.types) bool;
    inherit (lib.modules) mkIf;

    cfg = config.cosmos.services.kanidm;
  in {
    options.cosmos.services.kanidm.expose = mkOption {
      type = bool;
      default = false;
    };

    config = {
      cosmos.system.impermanence.persist.directories = [
        {
          directory = "/var/lib/kanidm";
          user = "kanidm";
          group = "kadidm";
          mode = "0750";
        }
      ];

      sops.secrets = {
        "keys/kanidm/admin-password".owner = "kanidm";
        "keys/kanidm/idm-admin-password".owner = "kanidm";
        "keys/pangolin/oauth-client-secret".owner = "kanidm";
        "keys/immich/oauth-client-secret".owner = "kanidm";
      };

      users.users.kanidm.extraGroups = ["acme"];

      services.kanidm = {
        package = pkgs.kanidmWithSecretProvisioning_1_10;
        server = {
          enable = true;
          settings = {
            domain = "lvdar.nl";
            origin = "https://auth.lvdar.nl";
            tls_chain = "/var/lib/acme/lvdar.nl/fullchain.pem";
            tls_key = "/var/lib/acme/lvdar.nl/key.pem";

            # nixpkgs defaults this to loopback, which is right only while the
            # local nginx vhost fronts it. Under edge termination netbird-proxy
            # dials `peer:8443` over the mesh and a loopback socket refuses it.
            # Reach stays governed by the firewall, which opens 8443 on wt0
            # alone (netbird.client.exposedPorts on endeavour).
            bindaddress =
              if config.cosmos.networking.edgeTerminated
              then "0.0.0.0:8443"
              else "127.0.0.1:8443";

            # Who may set the client address. Trusting the wrong hop lets a
            # client forge its own IP, and kanidm rate-limits per source, so
            # this tracks whatever actually sits in front: nginx on loopback,
            # or netbird-proxy arriving from the mesh. 100.64.0.0/10 is the
            # CGNAT range NetBird assigns peers from; the interface is only
            # reachable by enrolled peers.
            http_client_address_info.x-forward-for =
              if config.cosmos.networking.edgeTerminated
              then ["100.64.0.0/10"]
              else ["127.0.0.1"];
          };
        };

        provision = {
          enable = true;
          adminPasswordFile = config.sops.secrets."keys/kanidm/admin-password".path;
          idmAdminPasswordFile = config.sops.secrets."keys/kanidm/idm-admin-password".path;

          persons.lvdar = {
            displayName = "lvdar";
            mailAddresses = ["lars@lvdar.nl"];
          };

          groups = {
            users.members = ["lvdar"];
            pangolin-users = {
              overwriteMembers = false;
              members = ["lvdar"];
            };
            pangolin-admin.members = ["lvdar"];
            immich-users = {
              overwriteMembers = false;
              members = ["lvdar"];
            };
            immich-admin.members = ["lvdar"];
            opencloud-users = {
              overwriteMembers = false;
              members = ["lvdar"];
            };
            opencloud-admin.members = ["lvdar"];
            netbird-users = {
              overwriteMembers = false;
              members = ["lvdar"];
            };
            netbird-admin.members = ["lvdar"];
          };
          systems.oauth2 = {
            # The NetBird dashboard is a browser app, so it authenticates with
            # PKCE and holds no client secret — hence `public`. The client name
            # doubles as the audience NetBird's management server expects.
            netbird = {
              displayName = "NetBird";
              public = true;
              # These must match the dashboard's AUTH_REDIRECT_URI and
              # AUTH_SILENT_REDIRECT_URI, which services/netbird.nix overrides
              # to fragment-free paths precisely so these can exist.
              #
              # By default the dashboard is a hash-routed SPA redirecting to
              # `/#callback`, and kanidm can never match that: it strips the
              # fragment from configured origins on load (RFC 6749 §3.1.2 says a
              # redirect_uri must not contain one) while the incoming
              # redirect_uri keeps it — oauth2.rs:788 against :2301 — so under
              # strict matching they are never equal, however exactly the
              # fragment is spelled. See kanidm#3217, whose reporter hit this
              # with NetBird specifically.
              #
              # The fix is on NetBird's side rather than relaxing kanidm, so
              # strict redirect validation stays on. The paths it redirects to
              # are deliberately ones the dashboard has no page at — see the
              # AUTH_REDIRECT_URI comment in services/netbird.nix.
              #
              originUrl = [
                "https://netbird.lvdar.nl/callback"
                "https://netbird.lvdar.nl/silent-callback"
                # The CLI's device-login flow listens here. Peers enroll with
                # setup keys so this is not on the critical path, but leaving it
                # out would make an interactive `netbird up` fail confusingly.
                "http://localhost:53000/"
              ];
              originLanding = "https://netbird.lvdar.nl";
              scopeMaps.netbird-users = ["openid" "profile" "email"];
              claimMaps.groups = {
                joinType = "array";
                valuesByGroup = {
                  netbird-users = ["user"];
                  netbird-admin = ["admin"];
                };
              };
            };

            pangolin = {
              displayName = "Pangolin";
              basicSecretFile = config.sops.secrets."keys/pangolin/oauth-client-secret".path;
              originUrl = "https://pangolin.lvdar.nl/auth/idp/1/oidc/callback";
              originLanding = "https://pangolin.lvdar.nl";
              scopeMaps.pangolin-users = ["openid" "profile" "email"];
              claimMaps.groups = {
                joinType = "array";
                valuesByGroup = {
                  pangolin-users = ["cosmos"];
                  pangolin-admin = ["admin"];
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
              scopeMaps.opencloud-users = ["openid" "profile" "email" "opencloud_groups"];
              claimMaps.opencloud_groups = {
                joinType = "array";
                valuesByGroup = {
                  opencloud-users = ["user"];
                  opencloud-admin = ["admin"];
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
              scopeMaps.immich-users = ["openid" "profile" "email"];
              claimMaps.immich_groups = {
                joinType = "array";
                valuesByGroup.immich-admin = ["admin"];
              };
            };
          };
        };
      };

      # Dropped when the edge terminates TLS. kanidm keeps its own certificate
      # either way — it serves HTTPS on 8443 itself, which is what the edge
      # target points at.
      services.nginx.virtualHosts = mkIf (cfg.expose && !config.cosmos.networking.edgeTerminated) {
        "auth.lvdar.nl" = {
          forceSSL = true;
          enableACME = false;
          sslCertificate = "/var/lib/acme/lvdar.nl/fullchain.pem";
          sslCertificateKey = "/var/lib/acme/lvdar.nl/key.pem";
          locations."/".proxyPass = "https://127.0.0.1:8443";
        };
      };
    };
  };
}
