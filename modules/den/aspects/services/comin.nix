# services.comin — GitOps deployment: hosts pull their own config.
#
# Pulling, not pushing: no key grants root on the fleet. Pulls the knot over
# public HTTPS, so if the knot is down nothing deploys (the correct failure).
# No magic rollback — recovery is the bootloader menu.
# Not fleet-wide: pioneer would build on a Pi 3; voyager would switch itself
# out from under whoever is typing on it.
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

        # Pinned from api.github.com/meta; hence StrictHostKeyChecking=yes.
        programs.ssh.knownHosts."github.com" = {
          hostNames = ["github.com"];
          publicKey = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIOMqqnkVzrm0SdG6UOoqKLsabgH5C9okWi0dh2l9GKJl";
        };

        # Scoped to this unit: only comin's flake fetches may use this key.
        systemd.services.comin.environment.GIT_SSH_COMMAND = "ssh -i ${cfg.secretsKeyFile} -o IdentitiesOnly=yes -o StrictHostKeyChecking=yes";

        # gcroots pins the last built generation against GC before switch.
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
              # comin calls this `main` regardless: "the branch to switch to".
              branches.main.name = cfg.deployBranch;

              # Test-activated and deliberately ungated.
              branches.testing.name = "testing";
              poller.period = cfg.pollSeconds;
            }
          ];

          exporter = {
            port = cfg.exporterPort;
            openFirewall = false;
          };
        };

        cosmos.services.netbird.client.exposedPorts = [cfg.exporterPort];
      };
    };
  };
}
