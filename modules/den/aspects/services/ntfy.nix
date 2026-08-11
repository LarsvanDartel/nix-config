# services.ntfy — the alert sink, and deliberately the only piece of the
# monitoring stack that does not live on endeavour.
#
# endeavour holds the metrics, the logs and the dashboards, because it is the
# only host with the RAM and the disk for them. But it is also the host whose
# death is the single most important thing to be told about, and an alerting
# path that runs there cannot report its own outage. gaia is independent of it,
# is already the public ingress, and is reachable from a phone over the plain
# internet — so it still works during exactly the failures worth waking up for:
# endeavour down, the mesh down, the house offline.
#
# Published rather than mesh-only for the same reason, and ungated: the ntfy
# app authenticates with a username and password, and cannot complete an
# interactive browser login against kanidm. It carries its own auth instead —
# `auth-default-access: deny-all` means an anonymous request can neither read
# nor write, so the topic name is not the secret.
{
  den,
  inputs,
  ...
}: {
  den.aspects.services.ntfy = {
    includes = [den.aspects.services.netbird.client];

    nixos = {
      config,
      lib,
      pkgs,
      ...
    }: let
      inherit (lib.options) mkOption;
      inherit (lib.types) port str;

      cfg = config.cosmos.services.ntfy;
      passwordFile = config.sops.secrets."keys/ntfy/password".path;

      # ntfy keeps users in a sqlite auth file, so the account is runtime state
      # rather than configuration. Reconciled on every start from the sops
      # value, which makes the secret the source of truth: rotate it there and
      # the account follows on the next deploy, instead of drifting until
      # someone remembers there is a database.
      provision = pkgs.writeShellApplication {
        name = "ntfy-provision";
        runtimeInputs = [config.services.ntfy-sh.package pkgs.gnugrep];
        text = ''
          export NTFY_PASSWORD
          NTFY_PASSWORD="$(cat "$CREDENTIALS_DIRECTORY/password")"

          if ntfy user list 2>/dev/null | grep -q '^user ${cfg.user}$'; then
            ntfy user change-pass ${cfg.user}
          else
            ntfy user add ${cfg.user}
          fi

          # Read as well as write: the same account is what the phone
          # subscribes with.
          ntfy access ${cfg.user} '${cfg.topic}' rw
        '';
      };
    in {
      options.cosmos.services.ntfy = {
        port = mkOption {
          type = port;
          default = 8095;
          description = ''
            Loopback/mesh port. Not 8080 or 8444 (netbird-proxy's health and
            debug endpoints), not 9090 (netbird management's metrics), not 4443
            or 9444 (the proxy and its TLS listener) — this host is crowded.
          '';
        };

        domain = mkOption {
          type = str;
          default = "ntfy.lvdar.nl";
          description = "Public name, which must match the published service.";
        };

        user = mkOption {
          type = str;
          default = "alerts";
          description = ''
            The single account every host publishes as and the phone subscribes
            with. Matches cosmos.system.notifyFailure.user.
          '';
        };

        topic = mkOption {
          type = str;
          default = "fleet";
          description = "The one topic. Matches cosmos.system.notifyFailure.topic.";
        };
      };

      config = {
        sops.secrets."keys/ntfy/password".sopsFile =
          builtins.toString inputs.nix-secrets + "/hosts/common/secrets.yaml";

        cosmos.system.impermanence.persist.directories = [
          {
            directory = "/var/lib/ntfy-sh";
            user = "ntfy-sh";
            group = "ntfy-sh";
            mode = "0750";
          }
        ];

        # netbird-proxy reaches it over the mesh like any other target, so the
        # port opens on wt0 and nowhere else.
        cosmos.services.netbird.client.exposedPorts = [cfg.port];

        services.ntfy-sh = {
          enable = true;
          settings = {
            base-url = "https://${cfg.domain}";
            listen-http = ":${toString cfg.port}";

            # TLS is terminated at the edge by netbird-proxy, so ntfy sees
            # plain HTTP and must be told to trust the forwarded headers —
            # without this every publisher looks like it came from the proxy
            # and rate limiting applies to all of them collectively.
            behind-proxy = true;

            auth-file = "/var/lib/ntfy-sh/user.db";
            auth-default-access = "deny-all";
          };
        };

        systemd.services.ntfy-sh.serviceConfig.LoadCredential = "password:${passwordFile}";

        systemd.services.ntfy-provision = {
          description = "Reconcile the ntfy account from sops";
          after = ["ntfy-sh.service"];
          requires = ["ntfy-sh.service"];
          wantedBy = ["multi-user.target"];
          serviceConfig = {
            Type = "oneshot";
            User = "ntfy-sh";
            Group = "ntfy-sh";
            ExecStart = lib.getExe provision;
            LoadCredential = "password:${passwordFile}";
            StateDirectory = "ntfy-sh";
          };
          environment.NTFY_AUTH_FILE = "/var/lib/ntfy-sh/user.db";
        };
      };
    };
  };
}
