# services.gewis-minutes-watcher — regenerates a TINO meeting bucket's
# minutes.typ outline from agenda.typ; design in _gewis/minutes-watcher.py.
{...}: {
  den.aspects.services.gewisMinutesWatcher.nixos = {
    config,
    lib,
    pkgs,
    ...
  }: let
    inherit (lib.options) mkOption;
    inherit (lib.types) int;

    cfg = config.cosmos.services.gewisMinutesWatcher;

    watcher = pkgs.writers.writePython3Bin "gewis-minutes-watcher" {} (
      builtins.readFile ./_gewis/minutes-watcher.py
    );
  in {
    options.cosmos.services.gewisMinutesWatcher = {
      pollSeconds = mkOption {
        type = int;
        default = 60;
        description = "How often to check meeting buckets for a new commit to agenda.typ.";
      };
    };

    config = {
      # Mint the key once via TINO's UI (or /var/lib/tino/api_keys.yml) with
      # *editor* access only — the watcher must not commit; committing stays a
      # human action. New committee buckets must be added to the key's access map.
      sops.secrets."keys/gewis-minutes-watcher/tino-api-key".owner = "tino";

      systemd.services.gewis-minutes-watcher = {
        description = "Regenerate TINO meeting minutes outlines from their agenda";
        wantedBy = ["multi-user.target"];
        after = ["tino.service"];
        wants = ["tino.service"];

        path = [pkgs.typst pkgs.gitMinimal];

        environment = {
          TINO_BUCKET_DIR = "/var/lib/tino/buckets";
          WATCHER_STATE_FILE = "/var/lib/gewis-minutes-watcher/state.json";
          WATCHER_POLL_SECONDS = toString cfg.pollSeconds;
        };

        serviceConfig = {
          # Runs as tino: it needs read access to every bucket that user owns.
          User = "tino";
          Group = "tino";
          StateDirectory = "gewis-minutes-watcher";
          LoadCredential = "tino-api-key:${config.sops.secrets."keys/gewis-minutes-watcher/tino-api-key".path}";
          ExecStart = pkgs.writeShellScript "gewis-minutes-watcher-start" ''
            export TINO_API_KEY
            TINO_API_KEY="$(cat "$CREDENTIALS_DIRECTORY/tino-api-key")"
            exec ${lib.getExe watcher}
          '';
          Restart = "always";
          RestartSec = 10;
        };
      };
    };
  };
}
