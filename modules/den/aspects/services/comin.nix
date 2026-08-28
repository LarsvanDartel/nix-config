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
    includes = [
      den.aspects.services.netbird.client
      den.aspects.core.sops
    ];

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
          example = "https://git.example.org/me/nix-config";
          description = ''
            The repository to pull, as the knot serves it over HTTPS.

            A DID rather than a name because that is how a knot addresses a
            repository — the same URL the spindle clones from in CI. Public
            read, so no credential; if the repo ever stops being public this
            needs an ssh_deploy_key_path and a key to go with it.
          '';
        };

        deployBranch = mkOption {
          type = str;
          default = "deploy";
          description = ''
            The branch comin switches to. Not `main`: services/build-gate.nix
            builds every host at main and fast-forwards this only when all
            three are green, so what a host deploys is by construction
            something that built.

            Must match cosmos.services.build-gate.deployBranch. They are
            separate literals because the gate runs on one host and comin runs
            on several, and den cannot read another host's config — the same
            constraint that makes gaia.nix hardcode endeavour's ports.

            Set this back to "main" on a host that should track HEAD directly,
            accepting that nothing checks it first.
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

        secretsKeyFile = mkOption {
          type = str;
          default = config.sops.secrets."keys/comin/nix-secrets-key".path;
          defaultText = "the comin nix-secrets sops secret";
          description = ''
            Read-only deploy key for the private nix-secrets repository.

            This is the thing that made comin look like it worked on endeavour
            and not on gaia, and the distinction is worth writing down. comin
            evaluates the flake *on the host*, so it fetches every input
            itself — unlike deploy-rs, which builds elsewhere and copies a
            finished closure over. nix-secrets is a `git+ssh` input that
            core/sops.nix forces at eval time, so every poll needs it.
            endeavour happened to have that exact revision in its store
            already, so the fetch was a cache hit and never touched the
            network; gaia never had it and failed every poll it ever made
            with "Host key verification failed". The moment nix-secrets is
            bumped, endeavour hits the same wall — this fixes both.

            Read-only and scoped to that one repository as a GitHub deploy
            key, not an account key. What it grants is sight of the
            *ciphertext*: sops age keys are per-host, so a host with this key
            still cannot decrypt another host's secrets.
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
        sops.secrets."keys/comin/nix-secrets-key" = {
          sopsFile = builtins.toString inputs.nix-secrets + "/hosts/common/secrets.yaml";
          mode = "0400";
        };

        # github.com's host key, pinned rather than accepted on first use.
        # Taken from api.github.com/meta, which is where GitHub publishes it.
        #
        # StrictHostKeyChecking below is `yes`, not `accept-new`: with the key
        # pinned here there is no first use left to accept, so anything that
        # does not match this is a failure rather than a new entry written to
        # a file nobody reads. That is the whole reason to pin it — a fetch
        # that silently trusts whatever answers is not meaningfully
        # authenticated.
        programs.ssh.knownHosts."github.com" = {
          hostNames = ["github.com"];
          publicKey = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIOMqqnkVzrm0SdG6UOoqKLsabgH5C9okWi0dh2l9GKJl";
        };

        # Scoped to this unit rather than dropped into /root/.ssh/config: the
        # key exists for comin's flake fetches and nothing else on the host has
        # any business using it.
        systemd.services.comin.environment.GIT_SSH_COMMAND = "ssh -i ${cfg.secretsKeyFile} -o IdentitiesOnly=yes -o StrictHostKeyChecking=yes";

        # gcroots is the part that matters: it pins the last generation comin
        # built so a GC between build and switch cannot delete it out from
        # under the deployer. store.json (deployment history) and the working
        # clone are merely expensive to lose — without this, every boot on an
        # impermanent host is a fresh clone of the whole repository.
        cosmos.system.impermanence.persist.directories = [
          {
            directory = "/var/lib/comin";
            user = "root";
            group = "root";
            mode = "0700";
          }
        ];

        services.comin = {
          enable = true;

          remotes = [
            {
              name = "origin";
              url = cfg.repository;
              # `deploy`, not `main` — this is the whole point of
              # services/build-gate.nix. main is where work lands; deploy is
              # where work that has built on all three hosts lands, advanced by
              # the gate and by nothing else. comin has no magic rollback, so
              # the difference is between a typo costing a git push and a typo
              # costing two production hosts.
              #
              # comin calls this option `main` regardless of the branch's name:
              # it means "the branch to switch to", as against `testing` below.
              branches.main.name = cfg.deployBranch;

              # comin's own default, named here because it is a feature worth
              # remembering: this branch is `test`-activated, not switched, so
              # it disappears on reboot. Deliberately left ungated — pushing to
              # `testing` is how you try something *without* waiting for the
              # gate, and it cannot outlive a reboot.
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
