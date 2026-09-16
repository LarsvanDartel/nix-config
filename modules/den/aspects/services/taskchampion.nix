# services.taskchampion — the sync server Taskwarrior 3 replicates against.
#
# The server half of TaskChampion (Taskwarrior 3 dropped taskd). Not a task
# database: every client holds a full replica and syncs an encrypted op log,
# so the server cannot read tasks (the client-side `sync.encryption_secret`
# is the real secret) and losing this directory loses nothing a surviving
# replica holds — hence "convenience, not survival" in hosts/endeavour.nix.
#
# Published ungated, like ntfy: native clients cannot complete a browser
# login. The client id is the only auth, and `--allow-client-id` is a
# command-line argument (world-readable in the store and `ps`), so the ids
# arrive as a systemd credential. The id protects integrity and the disk,
# not the contents: a leaked id lets someone append junk, not read.
{...}: {
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

    # Rebuilds upstream's ExecStart with the ids read at runtime. Everything
    # before the ids is taken from `serverCfg` deliberately, so upstream
    # changes to port, data dir or snapshot policy reach this too.
    start = pkgs.writeShellApplication {
      name = "taskchampion-sync-server-start";
      text = ''
        # `|| [ -n "$id" ]` because sops writes the secret with no trailing
        # newline, and a bare `read` returns false on the last line when there
        # is none — silently yielding an empty list, which the check below
        # then turns into a server that will not start.
        allow=()
        while read -r id || [ -n "$id" ]; do
          [ -n "$id" ] || continue
          allow+=(--allow-client-id "$id")
        done < "$CREDENTIALS_DIRECTORY/client-ids"

        # Refuse to start rather than serve everyone. An empty or unreadable
        # credential would otherwise produce a server with no allow-list at
        # all, which on a published port is the one failure mode that must not
        # be quiet.
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
        default = 10222;
        description = ''
          Upstream's own default. Opened on the netbird interface in
          hosts/endeavour.nix for replicas already on the mesh, and published
          publicly by gaia's netbird-proxy for those that are not.
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
      services.taskchampion-sync-server = {
        enable = true;
        inherit (cfg) port;

        # Bound wide: replicas arrive over the mesh or through gaia's proxy
        # (endeavour is edgeTerminated). The firewall limits reach — 10222
        # opens on the netbird interface alone.
        host = "0.0.0.0";

        # Pinned, not defaulted. Upstream ties this to stateVersion (on from
        # 26.05); DynamicUser + StateDirectory would put the data in
        # /var/lib/private, and the persist entry below would bind-mount the
        # symlink — every sync starting from nothing after a reboot. Same trap
        # as microbin.nix and ollama.nix; here it would arm itself on a
        # stateVersion bump.
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
