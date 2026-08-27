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
          default = [
            # The front door. Dotted, so it is probed as written rather than
            # as a subdomain — see the mapping below.
            "lvdar.nl"
            "jellyfin"
            "immich"
            "traccar"
            "seerr"
            "cloud"
            "grafana"
            "ntfy"
            "auth"
          ];
          description = ''
            Names to probe. A bare label is taken as a subdomain of lvdar.nl;
            a name containing a dot is used as the hostname as written, which
            is what lets the apex appear here alongside the rest.

            The published surface, not the internals: this is the half of the
            stack that has to keep working when endeavour does not, so it
            checks what a person would.

            `auth` is worth its place — kanidm failing takes grafana, opencloud
            and the netbird gate with it, and that is one alert rather than
            three confusing ones.
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

        services.gatus = {
          enable = true;
          settings = {
            web.port = cfg.port;

            # In memory, not sqlite on disk. nixpkgs runs gatus under
            # DynamicUser, which relocates a StateDirectory to
            # /var/lib/private — and an impermanence entry over that path is
            # the EBUSY that has already broken ntfy, crowdsec and
            # tile-traccar here.
            #
            # Nothing is lost that matters: this exists to say what is up now
            # and to alert on the transition. Uptime history over months is a
            # nice-to-have, and not worth the third instance of a trap this
            # repo keeps documenting.
            storage.type = "memory";

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
