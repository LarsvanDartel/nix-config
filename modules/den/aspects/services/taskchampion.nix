# services.taskchampion — the Taskwarrior 3 sync server; every client holds a full encrypted replica.
{...}: let
  # Option default and netbird-service target (see services/netbird.nix).
  defaultPort = 10222;
in {
  # Ungated: TaskChampion clients can't follow a redirect. The client id
  # (sops) is the allow-list; replicas encrypt client-side.
  den.aspects.services.taskchampion.netbird-service = {host, ...}: {
    task = {
      bearerAuth.enable = false;
      targets = [
        {
          peer = host.name;
          port = defaultPort;
        }
      ];
    };
  };

  den.aspects.services.taskchampion.nixos = {
    config,
    lib,
    pkgs,
    ...
  }: let
    inherit (lib.options) mkOption;
    inherit (lib.types) nullOr port str;
    inherit (lib.modules) mkForce mkIf;
    inherit (lib.meta) getExe;

    cfg = config.cosmos.services.taskchampion;
    serverCfg = config.services.taskchampion-sync-server;

    # Rebuilds upstream's ExecStart from `serverCfg`; client ids arrive as a systemd credential
    # because `--allow-client-id` on the command line is world-readable.
    start = pkgs.writeShellApplication {
      name = "taskchampion-sync-server-start";
      text = ''
        # `|| [ -n "$id" ]`: sops writes no trailing newline, so a bare `read` drops the last id.
        allow=()
        while read -r id || [ -n "$id" ]; do
          [ -n "$id" ] || continue
          allow+=(--allow-client-id "$id")
        done < "$CREDENTIALS_DIRECTORY/client-ids"

        # Refuse to start rather than serve everyone on a published port.
        if [ ''${#allow[@]} -eq 0 ]; then
          echo "no client ids in the credential; refusing to serve unrestricted" >&2
          exit 1
        fi

        exec ${getExe serverCfg.package} \
          --listen "${serverCfg.host}:${toString serverCfg.port}" \
          --data-dir ${serverCfg.dataDir} \
          --snapshot-versions ${toString serverCfg.snapshot.versions} \
          --snapshot-days ${toString serverCfg.snapshot.days} \
          "''${allow[@]}"
      '';
    };
  in {
    options.cosmos.services.taskchampion = {
      port = mkOption {
        type = port;
        default = defaultPort;
        description = ''
          Upstream's own default. Opened on the netbird interface for
          replicas already on the mesh, and published as `task` for those
          that are not.
        '';
      };

      clientIdFile = mkOption {
        type = nullOr str;
        default = null;
        example = "/run/secrets/keys/taskwarrior/client-id";
        description = ''
          File of client-id UUIDs, one per line, and the only ids the server
          will accept. Loaded as a systemd credential so the ids stay out of
          the store and out of `ps`.

          Null leaves upstream's own ExecStart in place, which accepts every
          id. Safe only on a port nothing else can reach.
        '';
      };
    };

    config = {
      cosmos.services.netbird.client.exposedPorts = [cfg.port];

      services.taskchampion-sync-server = {
        enable = true;
        inherit (cfg) port;

        # Bound wide: endeavour is edgeTerminated; the firewall limits reach.
        host = "0.0.0.0";

        # Pinned: upstream ties it to stateVersion, and with DynamicUser the persist entry bind-mounts
        # the /var/lib/private symlink, so every sync starts from nothing.
        dynamicUser = false;
      };

      systemd.services.taskchampion-sync-server.serviceConfig = mkIf (cfg.clientIdFile != null) {
        LoadCredential = ["client-ids:${cfg.clientIdFile}"];
        ExecStart = mkForce (getExe start);
      };

      cosmos.system.impermanence.persist.directories = [
        "/var/lib/taskchampion-sync-server"
      ];
    };
  };
}
