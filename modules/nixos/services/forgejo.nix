{...}: {
  flake.modules.nixos.forgejo = {
    config,
    pkgs,
    ...
  }: {
    cosmos.system.impermanence.persist.directories = [
      {
        directory = "/var/lib/forgejo";
        user = config.services.forgejo.user;
        group = config.services.forgejo.group;
        mode = "0750";
      }
    ];

    users = {
      users."gitea-runner" = {
        group = "gitea-runner";
        isSystemUser = true;
      };
      groups."gitea-runner" = {};
    };
    sops.secrets = {
      "keys/forgejo/runner-token" = {
        owner = "gitea-runner";
        group = "gitea-runner";
      };
    };

    services.forgejo = {
      enable = true;
    };

    virtualisation.podman.enable = true;

    services.gitea-actions-runner = {
      package = pkgs.forgejo-runner;
      instances = {
        test = {
          enable = true;
          tokenFile = config.sops.secrets."keys/forgejo/runner-token".path;
          url = "https://git.lvdar.nl";
          name = "local";
          hostPackages = [
            pkgs.bash
            pkgs.coreutils
            pkgs.curl
            pkgs.gawk
            pkgs.gitMinimal
            pkgs.gnused
            pkgs.nodejs
            pkgs.wget
            pkgs.nix
          ];
          labels = [
            "debian-latest:docker://node:18-bullseye"
            "ubuntu-latest:docker://node:18-bullseye"
            "native:host"
          ];
        };
      };
    };
  };
}
