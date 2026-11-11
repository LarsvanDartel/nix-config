# services.kanidm — identity provider.
#
# Apps declare their own groups and OAuth2 clients on the `kanidm-provision`
# quirk, in their own aspect; this collects them from every host. Moving an
# app (or kanidm) to another host therefore only changes host files.
#
# Entry shape: { groups.<name> = …; oauth2.<name> = …; } with the values of
# services.kanidm.provision.{groups,systems.oauth2}, except that a
# confidential client names its secret as `basicSecret = "<sops key>"`
# instead of a basicSecretFile path. That key must be in hosts/common, the
# one file both the app's host and kanidm's host can decrypt.
{
  den,
  inputs,
  ...
}: let
  inherit (den.lib.policy) pipe;

  # Not a netbird-service: gaia's nginx proxies auth.lvdar.nl here
  # (cosmos.services.netbird.oidc.idp).
  port = 8443;
in {
  den.quirks.kanidm-provision.description = "kanidm groups and OAuth2 clients, provisioned wherever kanidm runs";

  # den reads these argument names (host scope, host-entity filter), so
  # deadnix must not strip them as unused.
  # deadnix: skip
  den.policies.kanidm-provision = {host, ...}: [
    (pipe.from "kanidm-provision" [
      (pipe.collectAll (
        # deadnix: skip
        {host, ...}: true
      ))
    ])
  ];

  den.aspects.services.kanidm = {
    # Only the kanidm host collects: a fleet-wide collect on every host would
    # make each host's evaluation pull in every other host's config.
    includes = [den.policies.kanidm-provision];

    nixos = {
      config,
      lib,
      pkgs,
      kanidm-provision,
      ...
    }: let
      inherit (lib.options) mkOption;
      inherit (lib.types) bool;
      inherit (lib.modules) mkIf mkForce mkMerge;
      inherit (lib.attrsets) filterAttrs mapAttrs mapAttrs' nameValuePair optionalAttrs;

      cfg = config.cosmos.services.kanidm;
      commonSecrets = builtins.toString inputs.nix-secrets + "/hosts/common/secrets.yaml";
      secretName = client: "kanidm/oauth2/${client}";

      confidential = entry: filterAttrs (_: c: c ? basicSecret) (entry.oauth2 or {});

      toProvision = entry: {
        groups = entry.groups or {};
        systems.oauth2 =
          mapAttrs (
            name: client:
              removeAttrs client ["basicSecret"]
              // optionalAttrs (client ? basicSecret) {
                basicSecretFile = config.sops.secrets.${secretName name}.path;
              }
          )
          (entry.oauth2 or {});
      };

      toSecrets = entry:
        mapAttrs' (name: client:
          nameValuePair (secretName name) {
            key = client.basicSecret;
            sopsFile = commonSecrets;
            owner = "kanidm";
            # Provisioning runs in kanidm's ExecStartPost.
            restartUnits = ["kanidm.service"];
          })
        (confidential entry);
    in {
      options.cosmos.services.kanidm.expose = mkOption {
        type = bool;
        default = false;
      };

      config = {
        cosmos.services.netbird.client.exposedPorts = [port];

        cosmos.system.impermanence.persist.directories = [
          {
            directory = "/var/lib/kanidm";
            user = "kanidm";
            group = "kanidm";
            mode = "0750";
          }
        ];

        sops.secrets = mkMerge ([
            {
              "keys/kanidm/admin-password".owner = "kanidm";
              "keys/kanidm/idm-admin-password".owner = "kanidm";
              # API token of the `mail-sender` service account (member of
              # idm_message_senders only), created by hand: provisioning
              # cannot make service accounts or tokens.
              "keys/kanidm/mail-sender-token" = {};
            }
          ]
          ++ map toSecrets kanidm-provision);

        # kanidmd only queues mail (`kanidm system message-queue list`);
        # this sends it. It insists on TLS to the relay, hence gaia's
        # mesh-relay-tls rather than the plaintext :2525 the other services
        # use; hand-synced with services/stalwart.nix and gaia.nix relayClients.
        sops.templates."kanidm-mail-sender.toml" = {
          content = ''
            token = "${config.sops.placeholder."keys/kanidm/mail-sender-token"}"
            instance_display_name = "lvdar.nl"
            instance_url = "https://auth.lvdar.nl"
            mail_from_address = "auth@lvdar.nl"
            mail_reply_to_address = "lars@lvdar.nl"
            mail_relay = "smtps://mail-relay.lvdar.nl:2465"
            # Default */5: every poll logs on both ends and crosses gaia's
            # nginx, ~150k lines a day. Mail here is resets, fine at 30 s.
            schedule = "*/30 * * * * * *"
          '';
          # Root-owned and group-readable: the sender warns about a config
          # owned by its own uid.
          group = "kanidm-mail-sender";
          mode = "0440";
          restartUnits = ["kanidm-mail-sender.service"];
        };

        users.users.kanidm-mail-sender = {
          isSystemUser = true;
          group = "kanidm-mail-sender";
        };
        users.groups.kanidm-mail-sender = {};

        systemd.services.kanidm-mail-sender = {
          description = "kanidm outbound mail queue sender";
          after = ["kanidm.service" "network-online.target"];
          wants = ["network-online.target"];
          wantedBy = ["multi-user.target"];
          serviceConfig = {
            ExecStart = lib.escapeShellArgs [
              "${config.services.kanidm.package}/bin/kanidm-mail-sender"
              "--client-config"
              (pkgs.writeText "kanidm-mail-sender-client.toml" ''
                uri = "https://auth.lvdar.nl"
              '')
              "--mail-sender-config"
              config.sops.templates."kanidm-mail-sender.toml".path
            ];
            # Its default `kanidm_mail_sender=info` logs every poll twice;
            # failures are errors either way.
            Environment = "RUST_LOG=kanidm_client=warn,kanidm_mail_sender=warn";
            User = "kanidm-mail-sender";
            Group = "kanidm-mail-sender";
            Restart = "on-failure";
            RestartSec = "10s";
            NoNewPrivileges = true;
            ProtectSystem = "strict";
            ProtectHome = true;
            PrivateTmp = true;
          };
        };

        users.users.kanidm.extraGroups = ["acme"];

        services.kanidm = {
          package = pkgs.kanidmWithSecretProvisioning_1_12;
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
                then "0.0.0.0:${toString port}"
                else "127.0.0.1:${toString port}";

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

          provision = mkMerge ([
              {
                enable = true;
                adminPasswordFile = config.sops.secrets."keys/kanidm/admin-password".path;
                idmAdminPasswordFile = config.sops.secrets."keys/kanidm/idm-admin-password".path;

                persons.lvdar = {
                  displayName = "lvdar";
                  mailAddresses = ["lars@lvdar.nl"];
                };

                groups.users.members = ["lvdar"];
              }
            ]
            ++ map toProvision kanidm-provision);
        };

        # kanidm still serves HTTPS on 8443 itself with its own certificate.
        services.nginx.virtualHosts = mkIf (cfg.expose && !config.cosmos.networking.edgeTerminated) {
          "auth.lvdar.nl" = {
            forceSSL = true;
            enableACME = false;
            sslCertificate = "/var/lib/acme/lvdar.nl/fullchain.pem";
            sslCertificateKey = "/var/lib/acme/lvdar.nl/key.pem";
            locations."/".proxyPass = "https://127.0.0.1:${toString port}";
          };
        };
      };
    };
  };
}
