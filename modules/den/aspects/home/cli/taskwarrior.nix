# home.taskwarrior (+ taskwarrior-tui, and the sync block for services.taskchampion)
#
# Split across nixos and homeManager: taskrc can't read a secret from a file,
# only `include` one, so the nixos half renders the sync stanza into a sops template.
{
  den,
  inputs,
  ...
}: {
  den.aspects.home.taskwarrior = {
    includes = [den.aspects.core.sops];

    nixos = {
      config,
      lib,
      ...
    }: let
      inherit (lib.options) mkOption;
      inherit (lib.types) nullOr str;
      inherit (lib.modules) mkIf;

      cfg = config.cosmos.programs.taskwarrior.sync;
      userName = config.cosmos.user.name;
    in {
      options.cosmos.programs.taskwarrior.sync = {
        serverUrl = mkOption {
          type = nullOr str;
          default = null;
          example = "http://endeavour.nb.lvdar.nl:10222";
          description = ''
            The taskchampion-sync-server to replicate against, or null to keep
            taskwarrior local. Plain http and a mesh name: the server is
            mesh-only (services/taskchampion.nix), and what protects the tasks
            is the client-side encryption rather than the transport.
          '';
        };
      };

      config = mkIf (cfg.serverUrl != null) {
        # Every replica presents the same UUID (a different id is a different,
        # empty task list). hosts/common holds the same value for endeavour's allow-list.
        sops.secrets = {
          "keys/taskwarrior/client-id" = {
            sopsFile = "${builtins.toString inputs.nix-secrets}/hosts/common/secrets.yaml";
            owner = userName;
          };
          "keys/taskwarrior/encryption-secret".owner = userName;
        };

        sops.templates."taskwarrior-sync.conf" = {
          content = ''
            sync.server.url=${cfg.serverUrl}
            sync.server.client_id=${config.sops.placeholder."keys/taskwarrior/client-id"}
            sync.encryption_secret=${config.sops.placeholder."keys/taskwarrior/encryption-secret"}
          '';
          owner = userName;
        };
      };
    };

    homeManager = {
      pkgs,
      lib,
      osConfig,
      ...
    }: let
      inherit (lib.meta) getExe;

      sync = osConfig.cosmos.programs.taskwarrior.sync;
    in {
      cosmos = {
        system.impermanence.persist.directories = [".local/share/task"];
        cli.shells.zsh.aliases.tt = "taskwarrior-tui";
      };

      programs.taskwarrior = {
        enable = true;
        package = pkgs.taskwarrior3;

        # rule.color.merge combines matching rules (overdue+scheduled becomes
        # unreadable). Last line of taskrc, so it overrides `task config`.
        extraConfig =
          ''
            rule.color.merge=0
          ''
          + lib.optionalString (sync.serverUrl != null) ''
            include ${osConfig.sops.templates."taskwarrior-sync.conf".path}
          '';
      };

      home.packages = [pkgs.taskwarrior-tui];

      xdg.desktopEntries.taskwarrior-tui = {
        exec = getExe pkgs.taskwarrior-tui;
        name = "Taskwarrior";
        terminal = true;
        type = "Application";
      };
    };
  };
}
