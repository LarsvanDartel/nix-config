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
    inherit (lib.modules) mkIf;

    cfg = config.cosmos.services.kanidm;
    # The gated services published by netbird-proxy (netbird.services in
    # hosts/gaia.nix). Literals: den cannot read another host's config — the
    # same reason the ports over there are literals. A name missing here is a
    # service nobody can reach; a name no service uses is a harmless empty
    # group. Each becomes a kanidm group AND a `groups` claim value, which
    # NetBird matches against the service's distribution list.
    gatedServices = [
      "suwayomi"
      "sabnzbd"
      "prowlarr"
      "radarr"
      "sonarr"
      "lidarr"
      "bazarr"

      # The only entry shared with people who administer nothing else — the
      # point of it being a group of its own rather than folded into another.
      "minecraft-control"
    ];

    # Groups that gate something *inside* a service, not access to it: not
    # published domains, they exist only to reach the `groups` claim the app
    # reads out of the X-NetBird-Groups header netbird-proxy stamps on the
    # request. One per Minecraft server, consumed by
    # cosmos.services.minecraft.control.access on endeavour — someone who
    # plays on one server has no business restarting the other.
    inAppGroups = [
      "netbird-minecraft-smp"
      "netbird-minecraft-hardcore"
    ];

    # Baseline mesh access. Kept in the claim because NetBird replaces a
    # user's auto-groups wholesale with whatever the token says — anything
    # omitted is taken away on next login, including the group the setup key
    # enrols peers into.
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

            # nixpkgs defaults this to loopback, right only while a local
            # nginx vhost fronts it. Under edge termination netbird-proxy
            # dials `peer:8443` over the mesh and a loopback socket refuses.
            # Reach stays governed by the firewall (8443 on wt0 alone).
            bindaddress =
              if config.cosmos.networking.edgeTerminated
              then "0.0.0.0:8443"
              else "127.0.0.1:8443";

            # Who may set the client address: trusting the wrong hop lets a
            # client forge its IP, and kanidm rate-limits per source. Tracks
            # whatever actually sits in front — nginx on loopback, or
            # netbird-proxy from the mesh (100.64.0.0/10 is the CGNAT range
            # NetBird assigns peers from).
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

              # Grafana authenticates against kanidm directly, not behind
              # the netbird gate — its access lives here, not in the
              # netbird-* family above.
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
            # One group per gated service, plus the baseline. overwriteMembers is
            # off so members added by hand in kanidm survive a redeploy — these
            # exist precisely to be handed out to other people.
            // lib.genAttrs netbirdGroups (_: {
              overwriteMembers = false;
              members = ["lvdar"];
            });
          systems.oauth2 = {
            # The NetBird dashboard is a browser app, so it authenticates with
            # PKCE and holds no client secret — hence `public`. The client name
            # doubles as the audience NetBird's management server expects.
            netbird = {
              displayName = "NetBird";
              public = true;
              # Must match the dashboard's AUTH_REDIRECT_URI /
              # AUTH_SILENT_REDIRECT_URI, which services/netbird.nix overrides
              # to fragment-free paths precisely so these can exist: kanidm
              # strips the fragment from configured origins on load (RFC 6749
              # §3.1.2) while the incoming redirect_uri keeps it, so the
              # default hash-routed `/#callback` can never match under strict
              # validation (kanidm#3217, hit with NetBird specifically). The
              # fix is on NetBird's side, so strict matching stays on; the
              # paths are deliberately ones the dashboard has no page at —
              # see AUTH_REDIRECT_URI in services/netbird.nix.
              #
              originUrl = [
                "https://netbird.lvdar.nl/callback"
                "https://netbird.lvdar.nl/silent-callback"
                # Not the dashboard's — netbird-proxy's bearer auth, which
                # management handles centrally for every published domain
                # (HttpConfig.AuthCallbackURL in services/netbird.nix).
                "https://netbird.lvdar.nl/api/reverse-proxy/callback"
                # Where the CLI's PKCE flow listens — `netbird up` and
                # `netbird ssh`, which asks for a user token before it dials.
                # It takes the first of these two ports it can open
                # (PKCEAuthorizationFlow in services/netbird.nix), so both
                # must be allowed here.
                "http://localhost:53000/"
                "http://localhost:54000/"
              ];
              originLanding = "https://netbird.lvdar.nl";
              # Who may obtain a token at all, as opposed to what they reach
              # once they have one. Every netbird-* group, not just the mesh
              # baseline, because the two were once conflated and the failure
              # was unreadable: a person in netbird-minecraft-control and
              # nothing else got "Identity does not have access to the
              # requested scopes" — kanidm refusing to issue a token before
              # the service gate on gaia was ever consulted, pointing at the
              # wrong layer. Being in one of these grants a token and nothing
              # more; each service's distribution list still decides what it
              # opens. netbird-users remains the group that means mesh access
              # — see the claim map below for why it must also appear there.
              scopeMaps = lib.genAttrs netbirdGroups (_: ["openid" "profile" "email"]);

              # Each group contributes its own name. NetBird sets the user's
              # auto-groups to exactly this set, so the mapping is one-to-one
              # on purpose: no translation layer to get wrong, and the group
              # named in a service's bearerAuth is the group granted here.
              claimMaps.groups = {
                joinType = "array";
                valuesByGroup =
                  {netbird-admin = ["netbird-admin"];}
                  // lib.genAttrs netbirdGroups (g: [g]);
              };
            };

            # Confidential, not public: grafana runs on a server and can keep
            # a secret, and its OIDC flow is server-to-server for the token
            # exchange. `public` here would force PKCE-without-secret, which
            # is for browser apps like the netbird dashboard.
            grafana = {
              displayName = "Grafana";
              # Exactly what grafana derives from its root_url. kanidm matches
              # redirect URIs strictly — the netbird dashboard needed its
              # callbacks moved off hash routes for this same reason.
              originUrl = ["https://grafana.lvdar.nl/login/generic_oauth"];
              originLanding = "https://grafana.lvdar.nl";
              basicSecretFile = config.sops.secrets."keys/grafana/oauth-client-secret".path;
              # Grafana looks up the account by preferred_username.
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

            # Confidential like grafana (server-side code exchange). TINO's
            # admin check reads whatever claim TINO_OIDC_GROUPS_CLAIM names —
            # tino_groups below, not kanidm's own "groups": granting that
            # makes kanidm return the identity's *entire* raw group membership
            # as the claim. TINO stores the whole userinfo response in its
            # session cookie, and the raw list alone pushed Set-Cookie past
            # 9KB — browsers silently drop cookies over ~4KB, so the session
            # never persisted and every login bounced back to /login with no
            # error. tino_groups mirrors opencloud_groups/immich_groups.
            tino = {
              displayName = "TINO";
              originUrl = ["https://tino.lvdar.nl/oidc/callback"];
              originLanding = "https://tino.lvdar.nl";
              basicSecretFile = config.sops.secrets."keys/tino/oidc-client-secret".path;
              # TINO's authlib flow sends no PKCE code_challenge; kanidm
              # enforces PKCE on every client regardless of confidentiality
              # and rejects the bare authorize request with "No PKCE code
              # challenge was provided with client in enforced PKCE mode".
              allowInsecureClientDisablePkce = true;
              # TINO hardcodes "groups" as a *requested scope*, not just a
              # claim name, and kanidm refuses a token for any scope the
              # identity's scopeMaps does not grant. Unavoidable (TINO's own
              # code, not configurable), and granting it makes kanidm add its
              # raw "groups" claim regardless — tino_groups below coexists
              # with that; TINO simply never reads the raw one.
              scopeMaps.tino-users = ["openid" "profile" "email" "groups"];
              # Each entry a kanidm group mapped to itself, not just the
              # admin flag: TINO's bucket ACLs match `entry.group in
              # user.groups` against exactly these values, so a kanidm group
              # must be listed here before any bucket ACL can reference it.
              # tino-users here is what makes a "tino-users" ACL usable in
              # TINO's bucket-settings UI; a one-off single-member group
              # needs the same treatment.
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
