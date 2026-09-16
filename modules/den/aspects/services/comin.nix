# services.comin — GitOps deployment: hosts pull their own config.
#
# Hosts poll the knot and switch themselves when the deploy branch moves:
# pulling, not pushing, so no key anywhere grants root on the fleet and a
# compromised spindle can at worst fail a build. Pulls from the knot over
# public HTTPS (`info/refs` unauthenticated, verified), not the mesh, not
# GitHub — the cost is that the knot becomes load-bearing: if it is down,
# nothing deploys, which is the correct failure.
#
# No magic rollback, unlike deploy-rs — recovery is the bootloader menu.
# The `testing` branch gets `nixos-rebuild test`: try something on a host
# without making it the boot default.
#
# Not enabled fleet-wide; see per-host comments. pioneer would have to
# build on a Raspberry Pi 3; voyager would switch itself out from under
# whoever is typing on it.
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

        # github.com's host key, pinned (from api.github.com/meta).
        # StrictHostKeyChecking is `yes`, not `accept-new`: with the key pinned
        # there is no first use left to accept — a mismatch is a failure, not a
        # new entry written to a file nobody reads.
        programs.ssh.knownHosts."github.com" = {
          hostNames = ["github.com"];
          publicKey = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIOMqqnkVzrm0SdG6UOoqKLsabgH5C9okWi0dh2l9GKJl";
        };

        # Scoped to this unit, not /root/.ssh/config — only comin's flake
        # fetches have any business using this key.
        systemd.services.comin.environment.GIT_SSH_COMMAND = "ssh -i ${cfg.secretsKeyFile} -o IdentitiesOnly=yes -o StrictHostKeyChecking=yes";

        # gcroots matters: it pins the last generation comin built so a GC
        # between build and switch cannot delete it. store.json and the clone
        # are merely expensive to lose — unpersisted, every boot on an
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
              # `deploy`, not `main` — the whole point of services/build-gate.nix:
              # deploy is advanced by the gate and by nothing else, and comin has
              # no magic rollback. comin calls this option `main` regardless of
              # the branch's name: it means "the branch to switch to".
              branches.main.name = cfg.deployBranch;

              # comin's own default, named because it is worth remembering:
              # `testing` is test-activated, disappears on reboot, deliberately
              # ungated — the way to try something without waiting for the gate.
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
