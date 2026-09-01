# home.taskwarrior (+ taskwarrior-tui, and the sync block for services.taskchampion)
#
# Split across nixos and homeManager because the sync configuration is a
# secret: taskwarrior wants `sync.encryption_secret` as a literal in taskrc,
# and the only literal worth writing there is one that came out of sops. So the
# nixos half renders the whole sync stanza into a sops template owned by the
# user, and the homeManager half does nothing but `include` it — taskrc has no
# way to read a value from a file, but it can include one.
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
        # The id is not a per-device identifier: the TaskChampion protocol
        # "uses the term client to refer generically to all replicas
        # replicating a single task history", so every device on this list —
        # voyager and the phone — presents the same UUID. A different one is a
        # different, empty list, not a second seat at the same one.
        #
        # It is a credential rather than a name because the server is
        # published (services/taskchampion.nix), which is why it comes from
        # sops instead of being written here. hosts/common: endeavour needs the
        # same value for its allow-list.
        sops.secrets = {
          "keys/taskwarrior/client-id" = {
            sopsFile = "${builtins.toString inputs.nix-secrets}/hosts/common/secrets.yaml";
            owner = userName;
          };
          "keys/taskwarrior/encryption-secret".owner = userName;
        };

        # The whole sync stanza, not just the secrets: taskrc's `include` takes
        # a file, so keeping the url here too means one file to include and one
        # place where the sync configuration lives.
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

        # Last line of taskrc, and taskwarrior lets a later definition win — so
        # anything set by hand with `task config` earlier in the file is
        # overridden by what sops rendered, rather than silently shadowing it.
        extraConfig = lib.optionalString (sync.serverUrl != null) ''
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
