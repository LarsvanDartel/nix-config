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
          # Same file the server was configured with; ExecStartPost runs
          # inside the unit, so /var/lib/ntfy-sh resolves to the same place.
          export NTFY_AUTH_FILE=/var/lib/ntfy-sh/user.db
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

        # Deliberately NOT persisted, which is unusual here and worth the
        # explanation.
        #
        # nixpkgs runs ntfy under DynamicUser with a StateDirectory, and that
        # pair relocates state to /var/lib/private/ntfy-sh. An impermanence
        # entry for /var/lib/ntfy-sh bind-mounts the path systemd wants to
        # manage as a symlink, and the unit dies at STATE_DIRECTORY with
        # "Device or resource busy" — the same EBUSY that has already bitten
        # crowdsec and tile-traccar in this repo.
        #
        # The usual fix is to turn DynamicUser off. Not needed here, because
        # none of this state is worth keeping: the auth database holds one
        # account which is reconciled from sops on every start, and the cache
        # is undelivered messages for a push-alert topic, which are stale by
        # the time anything reboots. Reproducible state does not need
        # persisting, and not persisting it removes the conflict rather than
        # working around it.

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

        # Provisioning rides on ntfy's own unit rather than living in one of
        # its own. Under DynamicUser the uid is allocated per-start, so a
        # separate unit cannot reliably be the same user or see the same
        # StateDirectory; ExecStartPost inherits both, plus the credential.
        systemd.services.ntfy-sh.serviceConfig = {
          LoadCredential = "password:${passwordFile}";
          ExecStartPost = lib.getExe provision;
        };
      };
    };
  };
}
