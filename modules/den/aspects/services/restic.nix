# services.restic — the offsite copy, on a Hetzner Storage Box named stardust.
#
# Excludes the re-acquirable media library and regenerable caches, which keeps
# it ~42 GB. gaia overrides repository, paths, exclude and quiesceServices.
#
# Hetzner Storage Box traps: SSH keys must be registered through Hetzner's
# interface (authorized_keys over SFTP changes nothing). Port 22 takes RFC4716
# keys only; port 23 (needed for an `--append-only` guard) is closed.
{...}: {
  den.aspects.services.restic = {
    # No `includes = [services.prometheus]` for ResticStale: that would land
    # the whole metrics stack on gaia.
    nixos = {
      config,
      lib,
      pkgs,
      ...
    }: let
      inherit (lib.options) mkOption;
      inherit (lib.types) bool listOf str;

      cfg = config.cosmos.services.restic;

      sshKey = config.sops.secrets."keys/stardust/ssh-key".path;

      # Restore from the dump; a file copy of live PGDATA may not replay.
      pgBackupDir = "/var/backup/postgresql";
    in {
      options.cosmos.services.restic = {
        repository = mkOption {
          type = str;
          example = "sftp:user@backup.example.org:/host";
          description = ''
            The restic repository URL.

            The main account rather than a sub-account, because sub-accounts on
            this box cannot hold SSH keys — the console offers no field for it
            and the authorized_keys route does not work (see the header). The
            per-host directory is therefore a convention, not a boundary.
          '';
        };

        paths = mkOption {
          type = listOf str;
          default = [];
          example = ["/persist/var/lib/some-service" "/persist/home"];
          description = ''
            What to back up. Empty by default: which paths hold irreplaceable
            state is a fact about a host, not about restic, and a default here
            silently decides it for every host that includes this.
          '';
        };

        exclude = mkOption {
          type = listOf str;
          default = [
            # immich regenerates both from the originals in upload/.
            "/tank/media/library/images/thumbs"
            "/tank/media/library/images/encoded-video"
            # immich's own dumps; the pg_dumpall is the copy that gets restored.
            "/tank/media/library/images/backups"
            # Never restored; the largest churn in /var/lib/arr.
            "**/logs.db*"
            "**/*.log"
            "**/Backups/**"
            # 1.4 GB of re-downloadable data beside a 3.5 MB database.
            "/persist/var/lib/suwayomi-server/.local/share/Tachidesk/bin"
            "/persist/var/lib/suwayomi-server/.local/share/Tachidesk/cache"
            "/persist/var/lib/suwayomi-server/.local/share/Tachidesk/webUI"
            "/persist/var/lib/suwayomi-server/.local/share/Tachidesk/extensions"
            "/persist/var/lib/suwayomi-server/.cache"
          ];
          description = "Patterns excluded from every path above.";
        };

        quiesceServices = mkOption {
          type = listOf str;
          default = [
            "traccar.service"
            "knot.service"
            "minecraft-server-smp.service"
            "minecraft-server-hardcore.service"
          ];
          description = ''
            Units stopped for the duration of the run and started again after.

            For embedded databases with no dump tool. traccar is an H2 store and
            netbird management a live SQLite one, and the tangled knot keeps its
            own SQLite beside the repositories; a file-level copy of any of them
            while it is being written is not guaranteed to be a database, it is
            a database-shaped set of files that may or may not open. Postgres is
            absent from this list on purpose — it gets a real dump instead, and
            never has to stop.

            Minecraft is here for the same reason and is the one entry whose
            cost players notice: region files are written continuously and have
            no dump tool, so a live copy can capture a half-written chunk. The
            server is therefore down for the length of the 02:00 run. That is a
            nightly restart, which most Minecraft operators schedule on purpose
            anyway — but it is a real interruption rather than the few seconds
            the others cost, and it is named here so it is not a surprise.

            Named units, not a glob, which means a server renamed in
            hosts/endeavour.nix must be renamed here too or its worlds are
            backed up live. The option shape gives no way to append from the
            aspect that owns the server — a definition elsewhere would replace
            this default rather than extend it — so hand-sync is the price.

            The cost is bounded and paid at 02:00: on gaia this pauses new
            enrollments and ACL pushes for a few seconds, and pauses nothing
            else, because the mesh data plane is peer-to-peer WireGuard that
            does not route through management.
          '';
        };

        postgresDump = mkOption {
          type = bool;
          default = config.services.postgresql.enable;
          description = ''
            Whether to run pg_dumpall before the backup and copy the dump.

            Defaults to whether this host runs postgres at all, so gaia — which
            does not — gets neither the dump timer nor the persist entry for a
            directory that would stay empty forever.
          '';
        };

        schedule = mkOption {
          type = str;
          default = "02:00";
          description = ''
            OnCalendar for the nightly run.

            Ahead of the 03:00 transcode and clear of the scrub at 02:30 on the
            1st and 15th — all three compete for the same spindles, and the
            backup is the one that should not be slowed down.
          '';
        };

        retention = mkOption {
          type = listOf str;
          default = [
            "--keep-daily 7"
            "--keep-weekly 5"
            "--keep-monthly 12"
            "--keep-yearly 3"
          ];
          description = ''
            Pruning policy. Generous because the data is small and the box is
            1 TB: the expensive thing here is not storage, it is discovering
            that the corruption you are restoring from happened four months
            ago and every snapshot you kept already contains it.
          '';
        };
      };

      config = {
        sops.secrets = {
          "keys/stardust/password" = {};
          "keys/stardust/ssh-key" = {};
        };

        # Pinned, not accept-new: trusting first contact could send the only
        # offsite copy to somebody else's disk.
        programs.ssh.knownHosts."u649268.your-storagebox.de".publicKey = "ssh-rsa AAAAB3NzaC1yc2EAAAABIwAAAQEA5EB5p/5Hp3hGW1oHok+PIOH9Pbn7cnUiGmUEBrCVjnAw+HrKyN8bYVV0dIGllswYXwkG/+bgiBlE6IVIBAq+JwVWu1Sss3KarHY3OvFJUXZoZyRRg/Gc/+LRCE7lyKpwWQ70dbelGRyyJFH36eNv6ySXoUYtGkwlU5IVaHPApOxe4LHPZa/qhSRbPo2hwoh0orCtgejRebNtW5nlx00DNFgsvn8Svz2cIYLxsPVzKgUxs8Zxsxgn+Q/UvR7uq4AbAhyBMLxv7DjJ1pc7PJocuTno2Rw9uMZi1gkjbnmiOh6TTXIEWbnroyIhwc8555uto9melEUmWNQ+C+PwAK+MPw==";

        # immich's database is the index for the photos; blobs without it are
        # files nothing can find.
        services.postgresqlBackup = lib.mkIf cfg.postgresDump {
          enable = true;
          backupAll = true;
          location = pgBackupDir;
          startAt = "01:30";
        };

        cosmos.system.impermanence.persist.directories =
          lib.optional cfg.postgresDump {
            directory = pgBackupDir;
            user = "postgres";
            group = "postgres";
            mode = "0700";
          }
          ++ [
            {
              # Rebuilding re-reads index files from the far end every night.
              directory = "/var/cache/restic-backups-stardust";
              user = "root";
              group = "root";
              mode = "0700";
            }
          ];

        services.restic.backups.stardust = {
          inherit (cfg) repository exclude;
          paths = cfg.paths ++ lib.optional cfg.postgresDump pgBackupDir;

          passwordFile = config.sops.secrets."keys/stardust/password".path;
          initialize = true;

          # -s sftp: the box runs mod_sftp, no shell to give.
          extraOptions = [
            "sftp.command='${lib.getExe pkgs.openssh} -p 22 -i ${sshKey} -o BatchMode=yes u649268@u649268.your-storagebox.de -s sftp'"
          ];

          timerConfig = {
            OnCalendar = cfg.schedule;
            # Unlike transcode: a missed backup leaves a permanent gap.
            Persistent = true;
            RandomizedDelaySec = "20m";
          };

          pruneOpts = cfg.retention;

          checkOpts = ["--read-data-subset=5%"];
          runCheck = true;

          # Cleanup runs regardless of success, so units cannot stay down.
          # mkIf, not "": an empty string would still wire a no-op ExecStopPost.
          backupPrepareCommand = lib.mkIf (cfg.quiesceServices != []) ''
            ${pkgs.systemd}/bin/systemctl stop ${lib.escapeShellArgs cfg.quiesceServices}
          '';
          backupCleanupCommand = lib.mkIf (cfg.quiesceServices != []) ''
            ${pkgs.systemd}/bin/systemctl start ${lib.escapeShellArgs cfg.quiesceServices}
          '';
        };
      };
    };
  };
}
