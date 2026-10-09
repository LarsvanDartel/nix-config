# services.kanidm — identity provider (OIDC for netbird/immich/opencloud/traccar).
{...}: {
  den.aspects.services.kanidm.nixos = {
    config,
    lib,
    pkgs,
    ...
  }: let
    inherit (lib.options) mkOption;
    inherit (lib.types) bool;
    inherit (lib.modules) mkIf mkForce;

    cfg = config.cosmos.services.kanidm;
    # Gated services from netbird.services in hosts/gaia.nix, hand-synced (den
    # cannot read another host's config). Each becomes a kanidm group AND a
    # `groups` claim value NetBird matches against distribution lists.
    gatedServices = [
      "suwayomi"
      "sabnzbd"
      "prowlarr"
      "radarr"
      "sonarr"
      "lidarr"
      "bazarr"
      "lingarr"

      # Shared with people who administer nothing else; keep it separate.
      "minecraft-control"
    ];

    # In-app permission groups (read via X-NetBird-Groups), not published
    # domains; consumed by cosmos.services.minecraft.control.access on
    # endeavour, one per server.
    inAppGroups = [
      "netbird-minecraft-smp"
      "netbird-minecraft-hardcore"
    ];

    # NetBird replaces auto-groups wholesale with the token's claim, so
    # omitting netbird-users would strip mesh access on next login.
    netbirdGroups =
      ["netbird-users"]
      ++ map (s: "netbird-${s}") gatedServices
      ++ inAppGroups;
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
          group = "kanidm";
          mode = "0750";
        }
      ];

      sops.secrets = {
        "keys/kanidm/admin-password".owner = "kanidm";
        "keys/kanidm/idm-admin-password".owner = "kanidm";
        "keys/immich/oauth-client-secret".owner = "kanidm";
      };

      users.users.kanidm.extraGroups = ["acme"];

      services.kanidm = {
        package = pkgs.kanidmWithSecretProvisioning_1_11;
        server = {
          enable = true;
          settings = {
            domain = "lvdar.nl";
            origin = "https://auth.lvdar.nl";
            tls_chain = "/var/lib/acme/lvdar.nl/fullchain.pem";
            tls_key = "/var/lib/acme/lvdar.nl/key.pem";

            # Under edge termination netbird-proxy dials peer:8443 over the
            # mesh; firewall limits 8443 to wt0.
            bindaddress =
              if config.cosmos.networking.edgeTerminated
              then "0.0.0.0:8443"
              else "127.0.0.1:8443";

            # Trusting the wrong hop lets clients forge their IP (kanidm
            # rate-limits per source). 100.64.0.0/10 = NetBird peer range.
            http_client_address_info.x-forward-for =
              if config.cosmos.networking.edgeTerminated
              then ["100.64.0.0/10"]
              else ["127.0.0.1"];

            # Upstream defaults this to a derivation; kanidm.nix's null filter
            # recurses into its .stdenv and trips deprecated-attr warnings,
            # fatal under abort-on-warn (broke at nixpkgs 494ce7f). Revisit if
            # server.entryManagement.migrations is ever used.
            migration_path = mkForce (toString (pkgs.linkFarm "kanidm-entry-management" []));
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

          groups =
            {
              users.members = ["lvdar"];
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
              netbird-admin.members = ["lvdar"];

              # Grafana authenticates against kanidm directly, not via netbird.
              grafana-users = {
                overwriteMembers = false;
                members = ["lvdar"];
              };
              grafana-admin.members = ["lvdar"];

              tino-users = {
                overwriteMembers = false;
                members = ["lvdar"];
              };
              tino-admin.members = ["lvdar"];
            }
            # overwriteMembers off so hand-added members survive a redeploy.
            // lib.genAttrs netbirdGroups (_: {
              overwriteMembers = false;
              members = ["lvdar"];
            });
          systems.oauth2 = {
            # Browser app using PKCE; the client name is the audience NetBird
            # management expects.
            netbird = {
              displayName = "NetBird";
              public = true;
              # kanidm strips fragments from configured origins (kanidm#3217),
              # so services/netbird.nix moves the dashboard callbacks to
              # fragment-free paths; keep these in sync with AUTH_REDIRECT_URI.
              originUrl = [
                "https://netbird.lvdar.nl/callback"
                "https://netbird.lvdar.nl/silent-callback"
                # netbird-proxy bearer auth (HttpConfig.AuthCallbackURL).
                "https://netbird.lvdar.nl/api/reverse-proxy/callback"
                # CLI PKCE flow uses the first free of these ports
                # (PKCEAuthorizationFlow in services/netbird.nix).
                "http://localhost:53000/"
                "http://localhost:54000/"
              ];
              originLanding = "https://netbird.lvdar.nl";
              # Every netbird-* group, not just netbird-users: otherwise a
              # member of only one service group is refused a token with a
              # misleading scopes error. Services' distribution lists still
              # decide access.
              scopeMaps = lib.genAttrs netbirdGroups (_: ["openid" "profile" "email"]);

              # One-to-one on purpose: NetBird sets auto-groups to exactly this.
              claimMaps.groups = {
                joinType = "array";
                valuesByGroup =
                  {netbird-admin = ["netbird-admin"];}
                  // lib.genAttrs netbirdGroups (g: [g]);
              };
            };

            grafana = {
              displayName = "Grafana";
              # kanidm matches redirect URIs strictly.
              originUrl = ["https://grafana.lvdar.nl/login/generic_oauth"];
              originLanding = "https://grafana.lvdar.nl";
              basicSecretFile = config.sops.secrets."keys/grafana/oauth-client-secret".path;
              preferShortUsername = true;
              scopeMaps.grafana-users = ["openid" "profile" "email"];
              claimMaps.grafana_role = {
                joinType = "array";
                valuesByGroup = {
                  grafana-users = ["Viewer"];
                  grafana-admin = ["Admin"];
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

            # Use tino_groups, not kanidm's raw "groups" claim as
            # TINO_OIDC_GROUPS_CLAIM: TINO stores userinfo in its cookie and
            # the raw list pushed it past 9KB, silently dropped by browsers.
            tino = {
              displayName = "TINO";
              originUrl = ["https://tino.lvdar.nl/oidc/callback"];
              originLanding = "https://tino.lvdar.nl";
              basicSecretFile = config.sops.secrets."keys/tino/oidc-client-secret".path;
              # TINO sends no PKCE challenge; kanidm enforces it otherwise.
              allowInsecureClientDisablePkce = true;
              # TINO hardcodes the "groups" scope; kanidm refuses ungranted
              # scopes. The resulting raw claim is simply unused.
              scopeMaps.tino-users = ["openid" "profile" "email" "groups"];
              # TINO bucket ACLs match against these values, so a kanidm group
              # must be listed here before an ACL can reference it.
              claimMaps.tino_groups = {
                joinType = "array";
                valuesByGroup = {
                  tino-admin = ["admins"];
                  tino-users = ["tino-users"];
                };
              };
            };
          };
        };
      };

      # kanidm still serves HTTPS on 8443 itself with its own certificate.
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
