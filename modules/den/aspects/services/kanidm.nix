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
            }
          ]
          ++ map toSecrets kanidm-provision);

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
            locations."/".proxyPass = "https://127.0.0.1:8443";
          };
        };
      };
    };
  };
}
