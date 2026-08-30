# services.gatus — probe the published surface from outside, and say so.
#
# On gaia deliberately, and it is the only part of the monitoring stack that
# can report the failure everything else is blind to. Prometheus, loki, grafana
# and alertmanager all live on endeavour; if that host goes away they go with
# it and nothing is left to notice. gaia is independent, so this keeps
# answering — and it alerts through the same ntfy topic, which also lives here.
#
# It probes the *public* names over the internet rather than peers over the
# mesh. That is the point: it exercises DNS, the edge's TLS, netbird-proxy's
# routing and the service itself, in the order a person would meet them. A
# mesh-side check would go green while the thing everyone actually uses is
# down.
{
  den,
  inputs,
  ...
}: {
  den.aspects.services.gatus = {
    includes = [den.aspects.services.ntfy];

    nixos = {
      config,
      lib,
      ...
    }: let
      inherit (lib.options) mkOption;
      inherit (lib.types) port listOf str;

      cfg = config.cosmos.services.gatus;
      ntfy = config.cosmos.services.ntfy;

      stateDir = "/var/lib/gatus";

      endpoint = name: url: {
        inherit name url;
        group = "published";
        interval = "2m";
        client.timeout = "15s";
        conditions = [
          "[STATUS] < 400"
          # 5 days is enough warning to renew by hand if ACME has quietly
          # stopped working, which is a failure that otherwise surfaces as a
          # browser error on a Sunday.
          "[CERTIFICATE_EXPIRATION] > 120h"
        ];
        alerts = [
          {
            type = "ntfy";
            enabled = true;
            # Three consecutive misses, not one. A single timeout on a 2m
            # interval is a blip; alerting on it is how a channel gets muted.
            failure-threshold = 3;
            success-threshold = 2;
            send-on-resolved = true;
            description = "${name} is not answering";
          }
        ];
      };
    in {
      options.cosmos.services.gatus = {
        port = mkOption {
          type = port;
          default = 8085;
          description = ''
            Free on this host. 443, 4443, 8080, 8444, 9090, 9444, 8076 and
            8095 are not — gaia is crowded, and 8080/8444 in particular belong
            to netbird-proxy's own health and debug endpoints.
          '';
        };

        endpoints = mkOption {
          type = listOf str;
          default = [];
          example = ["status.example.org" "auth"];
          description = ''
            Names to probe. A bare label is taken as a subdomain of the
            deployment's base domain; a name containing a dot is used as the
            hostname as written, which is what lets an apex be probed.

            Empty by default: what is worth watching is a property of a
            deployment, not of a status page.
          '';
        };
      };

      config = {
        sops = {
          secrets."keys/ntfy/password".sopsFile =
            builtins.toString inputs.nix-secrets + "/hosts/common/secrets.yaml";

          # Gatus expands ${VAR} in its config, so the credential arrives
          # through the environment and the generated YAML — which lands in the
          # world-readable nix store — carries only the variable name.
          templates."gatus.env".content = ''
            NTFY_PASSWORD=${config.sops.placeholder."keys/ntfy/password"}
          '';
        };

        # netbird-proxy dials this over the mesh like any other target.
        cosmos.services.netbird.client.exposedPorts = [cfg.port];

        # A static user, not the module's DynamicUser — the precondition for
        # keeping history at all on an impermanent host. Under DynamicUser,
        # StateDirectory lives at /var/lib/private/gatus behind a symlink, so
        # persisting /var/lib/gatus would persist the symlink and lose the
        # database on every boot.
        users.users.gatus = {
          isSystemUser = true;
          group = "gatus";
          home = stateDir;
        };
        users.groups.gatus = {};

        systemd.services.gatus.serviceConfig = {
          DynamicUser = lib.mkForce false;
          User = "gatus";
          Group = "gatus";
          StateDirectory = "gatus";
        };

        cosmos.system.impermanence.persist.directories = [
          {
            directory = stateDir;
            user = "gatus";
            group = "gatus";
            mode = "0750";
          }
        ];

        services.gatus = {
          enable = true;
          settings = {
            web.port = cfg.port;

            # On disk, so uptime history survives a restart.
            #
            # This used to be `memory`, because nixpkgs runs gatus under
            # DynamicUser, which relocates StateDirectory to /var/lib/private
            # and turns an impermanence entry over the visible path into the
            # EBUSY that has already broken ntfy, crowdsec and tile-traccar on
            # this host. The answer is not to give up the history but to stop
            # using DynamicUser, which is what open-webui and microbin already
            # do for the same reason — see the static user below.
            storage = {
              type = "sqlite";
              path = "${stateDir}/data.db";
            };

            alerting.ntfy = {
              # Scheme included: gatus takes a base URL, not a hostname.
              url = "https://${ntfy.domain}";
              topic = ntfy.topic;
              priority = 4;
              # The topic is deny-all, so this authenticates like every other
              # publisher in the fleet.
              username = ntfy.user;
              password = "\${NTFY_PASSWORD}";
            };

            endpoints =
              map (
                n:
                  endpoint n "https://${
                    if lib.hasInfix "." n
                    then n
                    else "${n}.lvdar.nl"
                  }"
              )
              cfg.endpoints;
          };
        };

        services.gatus.environmentFile = config.sops.templates."gatus.env".path;
      };
    };
  };
}
