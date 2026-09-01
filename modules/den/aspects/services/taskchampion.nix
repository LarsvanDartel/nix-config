# services.taskchampion — the sync server Taskwarrior 3 replicates against.
#
# Taskwarrior 3 dropped taskd entirely; the replacement is TaskChampion, and
# this is its server half. It is not a task database. Every client holds a
# complete replica and syncs an encrypted operation log through here, which has
# two consequences worth knowing before trusting it with anything:
#
#   * The server cannot read the tasks. The client encrypts with
#     `sync.encryption_secret`, which never leaves the client — so that secret,
#     not this host, is what stands between a copy of this directory and your
#     task list. Lose it on every client and the history here is unreadable.
#   * Losing this directory is not losing the tasks. Any surviving replica can
#     re-initialise sync and repopulate it. That is why the backup entry in
#     hosts/endeavour.nix calls it convenience rather than survival.
#
# **This is published to the internet**, so that a phone syncs without joining
# the mesh. TaskChampion has no authentication beyond knowing a client id, and
# nothing in front of it can add any — its clients are native apps that cannot
# complete a browser login, so gaia publishes it ungated like ntfy.
#
# The client id is therefore the whole of the access control, which makes it a
# credential in a way it would not be on a mesh-only port. Hence `clientIdFile`
# rather than a list of strings: `--allow-client-id` is a command-line
# argument, and a command line is world-readable in the store and in `ps`, so
# the ids arrive as a systemd credential and the arguments are built at start.
# The id is *not* what protects the contents — the encryption does that, and an
# attacker holding the id still sees ciphertext. What it protects is integrity
# and the disk: without the allow-list anyone could create replicas here, and
# with a leaked id they could append junk to yours.
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

    # Rebuilds the upstream module's ExecStart with the ids read at runtime.
    # Everything before the ids is copied from it deliberately: taking the
    # values from `serverCfg` rather than restating them means a change to
    # port, data dir or snapshot policy reaches this too.
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

        # Bound wide: replicas are other machines, reached either over the mesh
        # or through gaia's proxy, and endeavour is edgeTerminated so the
        # public path arrives from gaia over WireGuard. The firewall is what
        # limits reach — 10222 is opened on the netbird interface alone.
        host = "0.0.0.0";

        # Pinned, not defaulted. Upstream ties this to stateVersion — it turns
        # itself on from 26.05 — and a DynamicUser with StateDirectory puts the
        # data in /var/lib/private/… behind a symlink. The persist entry below
        # would then bind-mount the symlink and every sync would start from
        # nothing after a reboot. Same trap microbin.nix and ollama.nix each
        # document; here it would arm itself on a stateVersion bump rather than
        # on anything anybody wrote.
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
