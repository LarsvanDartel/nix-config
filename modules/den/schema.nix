# schema — per-host facts on the den host entity (den.hosts.<sys>.<name>.*).
#
# Entity data is plain flake-level data: any host's modules (and flake-level
# modules such as meta/deploy.nix) can read another host's facts here without
# evaluating that host's NixOS configuration.
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
          # A literal: NetBird's management server assigns it at enrollment,
          # so nothing in the config can produce it. Re-check after
          # re-enrolling a peer.
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

          # Matches cosmos.services.netbird.dnsDomain — hand-synced: reading
          # it from a nixosConfiguration would evaluate the host just to
          # deploy it.
          deployAddress = lib.mkOption {
            type = lib.types.str;
            default = "${config.name}.nb.lvdar.nl";
            description = "Address deploy-rs connects to.";
          };
        };
      })
    ];
  };
}
