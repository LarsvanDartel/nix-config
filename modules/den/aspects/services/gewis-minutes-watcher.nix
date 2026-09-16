# services.gewis-minutes-watcher — regenerates a TINO meeting bucket's
# minutes.typ outline from agenda.typ whenever a commit touches it. See
# _gewis/minutes-watcher.py's own docstring for the full design (bucket
# discovery, the heading-title merge, why writes go through TINO's API but
# reads hit the filesystem directly).
#
# TINO has no webhook, so this polls rather than reacts — see
# cosmos.services.gewisMinutesWatcher.pollSeconds.
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
      # The token itself has to be minted once through TINO's own UI —
      # POST /api/keys requires an authenticated user session, and there is
      # deliberately no admin bootstrap path around that.
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
          # Runs as tino directly rather than its own user + group
          # membership: it needs to read every meeting bucket under
          # /var/lib/tino/buckets, which is exactly what that user already
          # has, and nothing here needs privilege beyond that.
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
