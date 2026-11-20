# schema — per-host facts on the den host entity (den.hosts.<sys>.<name>.*).
{
  den,
  lib,
  ...
}: {
  den.policies.server-role = {host, ...}:
    lib.optional host.server (den.lib.policy.include den.aspects.roles.server);

  den.schema.host = {
    includes = [den.policies.server-role];

    imports = [
      ({config, ...}: {
        options = {
          # A literal NetBird management assigns at enrollment; re-check after re-enrolling a peer.
          meshAddress = lib.mkOption {
            type = lib.types.nullOr lib.types.str;
            default = null;
            description = "The host's NetBird mesh IPv4 address.";
          };

          server = lib.mkOption {
            type = lib.types.bool;
            default = false;
            description = "Headless server: gets roles.server.";
          };

          # Hand-synced with cosmos.services.netbird.dnsDomain: reading it from a
          # nixosConfiguration would evaluate the host just to deploy it.
          deployAddress = lib.mkOption {
            type = lib.types.str;
            default = "${config.name}.nb.lvdar.nl";
            description = "Address deploy-rs connects to.";
          };

          deployByDefault = lib.mkOption {
            type = lib.types.bool;
            default = true;
            description = "Whether a bare `deploy` includes this server; false still leaves it a node (`deploy .#<host>`).";
          };

          # Pinned in every host's known_hosts (core.ssh) and in endeavour's builder authorization.
          # Reinstalling with a fresh key means updating this and .sops.yaml together.
          sshHostKey = lib.mkOption {
            type = lib.types.nullOr lib.types.str;
            default = null;
            description = "The host's ed25519 SSH host public key (`ssh-ed25519 AAAA…`, no comment).";
          };
        };
      })
    ];
  };
}
