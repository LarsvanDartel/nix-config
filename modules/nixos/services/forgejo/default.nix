{
  config,
  lib,
  pkgs,
  ...
}: let
  inherit (lib.options) mkEnableOption;
  inherit (lib.modules) mkIf;

  cfg = config.cosmos.services.forgejo;
in {
  options.cosmos.services.forgejo = {
    enable = mkEnableOption "forgejo";
  };

  config = mkIf cfg.enable {
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
      # settings = {
      #   DEFAULT = {
      #     RUN_MODE = "dev";
      #   };
      #   server = {
      #     ROOT_URL = "https://git.lvdar.nl";
      #   };
      #   repository = {
      #     DEFAULT_PRIVATE = "private";
      #   };
      #   oauth2_client = {
      #     ENABLE_AUTO_REGISTRATION = true;
      #   };
      #   service = {
      #     # DISABLE_REGISTRATION = true;
      #     # ENABLE_BASIC_AUTHENTICATION = false;
      #     # ENABLE_INTERNAL_SIGNIN = false;
      #   };
      #   other = {
      #     SHOW_FOOTER_VERSION = false;
      #   };
      # };
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
