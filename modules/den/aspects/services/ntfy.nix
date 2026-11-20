# services.ntfy — the fleet alert sink, hosted off endeavour so it can report endeavour's outage.
{
  den,
  inputs,
  ...
}: let
  defaultPort = 8095;
in {
  den.aspects.services.ntfy = {
    includes = [den.aspects.services.netbird.client];

    # Ungated: the app uses username/password, and the outage notifier
    # must not depend on kanidm.
    netbird-service = {host, ...}: {
      ntfy = {
        bearerAuth.enable = false;
        targets = [
          {
            peer = host.name;
            port = defaultPort;
          }
        ];
      };
    };

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

      provision = pkgs.writeShellApplication {
        name = "ntfy-provision";
        runtimeInputs = [config.services.ntfy-sh.package pkgs.gnugrep];
        text = ''
          # Must match settings.auth-file; ExecStartPost shares the unit's namespace.
          export NTFY_AUTH_FILE=/var/lib/ntfy-sh/user.db
          export NTFY_PASSWORD
          NTFY_PASSWORD="$(cat "$CREDENTIALS_DIRECTORY/password")"

          # ExecStartPost starts as soon as the main process forks, before
          # `ntfy serve` has created the auth file: poll for it.
          for _ in $(seq 30); do
            ntfy user list >/dev/null 2>&1 && break
            sleep 1
          done

          # `ntfy user list` prints "user <name> (role: …)", not a bare name.
          if ntfy user list 2>/dev/null | grep -qE '^user ${cfg.user}( |$)'; then
            ntfy user change-pass ${cfg.user}
          else
            # Tolerated: if detection misfires, an existing account must not fail the unit.
            ntfy user add ${cfg.user} || true
          fi

          # rw: the phone subscribes with this same account.
          ntfy access ${cfg.user} '${cfg.topic}' rw
        '';
      };
    in {
      options.cosmos.services.ntfy = {
        port = mkOption {
          type = port;
          default = defaultPort;
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

        # Not persisted: under DynamicUser an impermanence entry on /var/lib/private
        # fails with EBUSY. The auth db is rebuilt from sops on every start.

        cosmos.services.netbird.client.exposedPorts = [cfg.port];

        # NoNewPrivileges unit: no exec transitions out of this profile.
        security.apparmor.policies.ntfy-sh = {
          inherit (config.cosmos.security.apparmor) state;
          profile = ''
            abi <abi/5.0>,
            include <tunables/global>

            profile ntfy-sh ${config.services.ntfy-sh.package}/bin/ntfy flags=(attach_disconnected,mediate_deleted) {
              include <abstractions/base-strict>
              include <abstractions/nameservice>
              include <abstractions/ssl_certs>

              capability net_bind_service,

              network inet stream,
              network inet6 stream,
              network inet dgram,
              network inet6 dgram,

              ${config.services.ntfy-sh.package}/bin/ntfy mr,

              /var/lib/{,private/}ntfy-sh/ rw,
              /var/lib/{,private/}ntfy-sh/** rwkl,
              /run/ntfy-sh/ rw,
              /run/ntfy-sh/** rwk,
              owner @{PROC}/@{pid}/{cgroup,mountinfo,stat,status,limits} r,
              @{sys}/fs/cgroup/** r,
              @{sys}/kernel/mm/transparent_hugepage/hpage_pmd_size r,
              /tmp/ r,
              owner /tmp/** rwk,

              deny /run/credentials/** rwlkmx,
              deny /run/secrets{,.d}/** rwlkmx,
              deny /run/secrets-for-users{,.d}/** rwlkmx,
              deny /persist/** rwlkmx,

              include if exists <local/ntfy-sh>
            }
          '';
        };

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
          # `-`: a failing provision must not fail activation, or deploy-rs rolls back the whole deploy.
          ExecStartPost = "-${lib.getExe provision}";
        };
      };
    };
  };
}
