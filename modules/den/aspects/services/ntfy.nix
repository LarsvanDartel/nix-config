# services.ntfy — the alert sink.
#
# On gaia, not endeavour: an alert path there cannot report endeavour's own
# outage. Ungated: the ntfy app cannot complete a kanidm login; it relies on
# `auth-default-access: deny-all` instead.
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

      # The sqlite auth db is reconciled from sops on every start.
      provision = pkgs.writeShellApplication {
        name = "ntfy-provision";
        runtimeInputs = [config.services.ntfy-sh.package pkgs.gnugrep];
        text = ''
          # Same file the server was configured with; ExecStartPost runs
          # inside the unit, so /var/lib/ntfy-sh resolves to the same place.
          export NTFY_AUTH_FILE=/var/lib/ntfy-sh/user.db
          export NTFY_PASSWORD
          NTFY_PASSWORD="$(cat "$CREDENTIALS_DIRECTORY/password")"

          # The state directory is not persisted (see below), so every restart
          # recreates the auth database from nothing, and this races the main
          # `ntfy serve` process for it: ExecStartPost starts as soon as the
          # process is forked, not once it has finished initializing, so
          # `ntfy user list` can run before the auth-file exists at all. That
          # failure was being swallowed — `user list` errored, the grep found
          # no match, `user add` then *also* failed silently under `|| true`
          # for the same reason — so the account was never created and every
          # publish 401'd until the next restart happened to win the race.
          # Poll instead of trusting the first attempt.
          for _ in $(seq 30); do
            ntfy user list >/dev/null 2>&1 && break
            sleep 1
          done

          # `ntfy user list` prints "user alerts (role: user, tier: none)", not
          # a bare name, so anchoring on '^user <name>$' never matched and this
          # always took the `add` branch. That only worked once: every restart
          # after the account existed died on "user alerts already exists".
          # Latent until something restarted ntfy, which a reboot finally did.
          if ntfy user list 2>/dev/null | grep -qE '^user ${cfg.user}( |$)'; then
            ntfy user change-pass ${cfg.user}
          else
            # Still tolerated on failure: if the detection above is ever wrong
            # again, the account already existing is the harmless case and must
            # not be what takes the server down.
            ntfy user add ${cfg.user} || true
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

        # Deliberately NOT persisted: under DynamicUser an impermanence entry
        # on /var/lib/private is the EBUSY that killed crowdsec and
        # tile-traccar. The auth db is rebuilt from sops on every start.

        cosmos.services.netbird.client.exposedPorts = [cfg.port];

        services.ntfy-sh = {
          enable = true;
          settings = {
            base-url = "https://${cfg.domain}";
            listen-http = ":${toString cfg.port}";

            # TLS ends at netbird-proxy; without behind-proxy every publisher
            # shares the proxy's address for rate limiting.
            behind-proxy = true;

            auth-file = "/var/lib/ntfy-sh/user.db";
            auth-default-access = "deny-all";
          };
        };

        # ExecStartPost, not a separate unit: under DynamicUser only this
        # inherits the same uid and StateDirectory.
        systemd.services.ntfy-sh.serviceConfig = {
          LoadCredential = "password:${passwordFile}";
          # `-`: a failing provision must not fail activation — deploy-rs
          # then rolls the whole deploy back (happened; gaia was undeployable).
          ExecStartPost = "-${lib.getExe provision}";
        };
      };
    };
  };
}
