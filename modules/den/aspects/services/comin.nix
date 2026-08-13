# services.comin — GitOps deployment: hosts pull their own config.
#
# Replaces running deploy-rs by hand for the hosts that opt in. A host polls
# the knot, and when main moves it builds and switches itself. The direction of
# the arrow is the point: nothing needs credentials to reach the fleet, so
# there is no key anywhere that grants root on four machines. That was the
# objection to deploying from CI, and pulling does not have it — a compromised
# spindle can at worst fail a build, not push a system.
#
# It pulls from the knot over public HTTPS, not over the mesh and not from
# GitHub. The knot serves `info/refs` unauthenticated (verified), so no
# credential is involved at all, and the fleet stops depending on a remote it
# does not own for its own deployments. The cost is that endeavour becomes
# load-bearing for everyone's updates — if the knot is down nothing deploys,
# which is the correct failure: nothing deploys, rather than something wrong
# deploying.
#
# Two safety properties worth knowing before trusting it:
#
#   * comin builds and switches on the machine itself. There is no
#     magic-rollback the way deploy-rs has one — a configuration that breaks
#     networking breaks it, and the recovery is the bootloader menu.
#   * pushing to the `testing` branch gets `nixos-rebuild test`: activated but
#     not made the boot default. That is the way to try something on a host
#     that is a nuisance to visit physically.
#
# Not enabled fleet-wide on purpose; see the comments on each host. In
# particular pioneer would have to *build* on a Raspberry Pi 3, and voyager
# would switch itself out from under whoever is typing on it.
{
  den,
  inputs,
  ...
}: {
  flake-file.inputs.comin = {
    url = "github:nlewo/comin";
    inputs.nixpkgs.follows = "nixpkgs";
  };

  den.aspects.services.comin = {
    includes = [den.aspects.services.netbird.client];

    nixos = {
      config,
      lib,
      ...
    }: let
      inherit (lib.options) mkOption;
      inherit (lib.types) ints str;

      cfg = config.cosmos.services.comin;
    in {
      imports = [inputs.comin.nixosModules.comin];

      options.cosmos.services.comin = {
        repository = mkOption {
          type = str;
          default = "https://knot.lvdar.nl/did:plc:a3erncqfgkcxu3yl6fpjfmwf";
          description = ''
            The repository to pull, as the knot serves it over HTTPS.

            A DID rather than a name because that is how a knot addresses a
            repository — the same URL the spindle clones from in CI. Public
            read, so no credential; if the repo ever stops being public this
            needs an ssh_deploy_key_path and a key to go with it.
          '';
        };

        pollSeconds = mkOption {
          type = ints.positive;
          default = 300;
          description = ''
            How often to check for new commits.

            Five minutes rather than comin's 60 s default. A poll is a git
            fetch against endeavour, and with several hosts doing it there is
            no reason to make that a per-minute event when nothing here is
            deployed on a timescale that cares.
          '';
        };

        exporterPort = mkOption {
          type = ints.positive;
          default = 4243;
          description = ''
            Prometheus exporter. Worth having: this is the first thing in the
            fleet that can answer "did that host actually take the new config,
            and when" without asking the host directly.
          '';
        };
      };

      config = {
        services.comin = {
          enable = true;

          remotes = [
            {
              name = "origin";
              url = cfg.repository;
              branches.main.name = "main";
              # comin's own default, named here because it is a feature worth
              # remembering: this branch is `test`-activated, not switched, so
              # it disappears on reboot.
              branches.testing.name = "testing";
              poller.period = cfg.pollSeconds;
            }
          ];

          exporter = {
            port = cfg.exporterPort;
            # Reachable over the mesh only, via the netbird rule below —
            # never by opening it on every interface.
            openFirewall = false;
          };
        };

        cosmos.services.netbird.client.exposedPorts = [cfg.exporterPort];
      };
    };
  };
}
