# services.restic — the offsite copy, on a Hetzner Storage Box named stardust.
#
# Everything else in this repo protects against a component failing. This is
# the only thing that protects against the machine being gone: raidz1 survives
# a disk, sanoid survives a bad delete, and neither survives a fire, a theft,
# or a `zpool destroy`. Before this existed there was no second copy of
# anything, anywhere.
#
# What is here and what is deliberately not:
#
#   in   the immich photo originals (40 GB, the only irreplaceable bytes on
#        the host), the postgres dump behind them, kanidm (5 MB, and the
#        identity root for every OIDC login in the fleet), traccar's location
#        history, the arr configs, grafana, opencloud, and home.
#   out  /tank/media/library/{movies,shows} — 673 GB the arr stack can
#        re-acquire; jellyfin's 16 GB of regenerable metadata and transcode
#        cache; loki and prometheus, which are observability about the past
#        rather than state; and every *thumbs* or *encoded-video* directory,
#        which immich rebuilds from the originals.
#
# That split is the whole reason this is affordable: ~42 GB on a 1 TB box
# instead of 715 GB.
#
# This aspect is included by endeavour and gaia both. The option defaults below
# describe **endeavour**, because it holds essentially every irreplaceable byte
# in the fleet and the reasoning above only makes sense next to its values;
# gaia overrides repository, paths, exclude and quiesceServices in gaia.nix,
# where the ~146 MB it actually needs is enumerated with its own reasoning.
#
# Named for the NASA sample-return craft — it flew through comet Wild 2's coma,
# caught the grains in aerogel and dropped the capsule in Utah in 2006, which
# is a backup described as a spacecraft. Genesis had the same job two years
# earlier, its chute never opened, and it hit the desert at 300 km/h; that one
# is not a name you give a backup.
#
# Two things about the Storage Box that cost an evening to learn, recorded so
# they do not cost another one:
#
#   * SSH keys must be registered through Hetzner's own interface. Writing
#     ~/.ssh/authorized_keys over SFTP persists the file and changes nothing —
#     the file is a rendering of Hetzner's key store, not the thing consulted
#     at login. ssh-copy-id appears to succeed and does not work.
#   * port 22 accepts keys in RFC4716 form only, port 23 in OpenSSH form only.
#     This generation of box has 23 closed, which also rules out the
#     `command="rclone serve restic --append-only"` trick that would otherwise
#     give real ransomware protection. Worth revisiting if Hetzner ever opens
#     23 here.
{...}: {
  den.aspects.services.restic = {
    # Deliberately no `includes = [services.prometheus]`, though the ResticStale
    # alert lives there. endeavour includes prometheus in its own right, and
    # pulling it in from here would land the whole metrics stack on gaia — a
    # 3.7 GiB VPS that services/prometheus.nix explicitly rules out as a host.
    # The alert has no instance filter, so it covers whichever hosts export the
    # timer; the dependency runs alert → backup, not backup → alert.
    nixos = {
      config,
      lib,
      pkgs,
      ...
    }: let
      inherit (lib.options) mkOption;
      inherit (lib.types) bool listOf str path;

      cfg = config.cosmos.services.restic;

      sshKey = config.sops.secrets."keys/stardust/ssh-key".path;

      # Backups run at 02:00; postgres is dumped just before, and the dump is
      # what gets copied. A file-level copy of a live PGDATA is not a database,
      # it is a database-shaped set of files that may or may not replay.
      pgBackupDir = "/var/backup/postgresql";
    in {
      options.cosmos.services.restic = {
        repository = mkOption {
          type = str;
          default = "sftp:u649268@u649268.your-storagebox.de:/endeavour";
          description = ''
            The restic repository URL.

            The main account rather than a sub-account, because sub-accounts on
            this box cannot hold SSH keys — the console offers no field for it
            and the authorized_keys route does not work (see the header). The
            per-host directory is therefore a convention, not a boundary.
          '';
        };

        paths = mkOption {
          type = listOf path;
          default = [
            pgBackupDir
            "/persist/var/lib/kanidm"
            "/persist/var/lib/traccar"
            "/persist/var/lib/arr"
            "/persist/var/lib/grafana"
            "/persist/var/lib/opencloud"
            "/persist/home"
            "/persist/etc/opencloud"
            "/tank/opencloud"
            "/tank/media/library/images"
          ];
          description = ''
            What to copy. Read through /persist rather than /var/lib on
            purpose: those are the same bytes, but the persist path is the one
            that survives a root rollback, so a backup taken from it cannot
            silently capture something impermanence was about to discard.

            /persist/etc/opencloud carries opencloud.yaml — the JWT signing
            key, the machine-auth key and the LDAP bind passwords. Without it
            every account and every blob under dataDir is orphaned, which makes
            a 4 KB file the single highest-value entry in this list.
          '';
        };

        exclude = mkOption {
          type = listOf str;
          default = [
            # immich regenerates both from the originals in upload/.
            "/tank/media/library/images/thumbs"
            "/tank/media/library/images/encoded-video"
            # immich's own periodic DB dumps. The pg_dumpall above is the copy
            # that gets restored; keeping both doubles the churn for nothing.
            "/tank/media/library/images/backups"
            # The arrs write these continuously and nobody has ever restored
            # one. They are also the largest churning files in /var/lib/arr,
            # so excluding them is most of what keeps the nightly delta small.
            "**/logs.db*"
            "**/*.log"
            "**/Backups/**"
          ];
          description = "Patterns excluded from every path above.";
        };

        quiesceServices = mkOption {
          type = listOf str;
          default = ["traccar.service"];
          description = ''
            Units stopped for the duration of the run and started again after.

            For embedded databases with no dump tool. traccar is an H2 store and
            netbird management a live SQLite one; a file-level copy of either
            while it is being written is not guaranteed to be a database, it is
            a database-shaped set of files that may or may not open. Postgres is
            absent from this list on purpose — it gets a real dump instead, and
            never has to stop.

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

        # Hetzner shares one RSA host key across storage boxes, and it is the
        # only algorithm this one offers. Pinned rather than left to
        # StrictHostKeyChecking=accept-new: an unattended job that trusts
        # whatever answers on first contact has no authentication of the
        # server at all, which for a backup target means happily encrypting
        # your only offsite copy to somebody else's disk.
        programs.ssh.knownHosts."u649268.your-storagebox.de".publicKey = "ssh-rsa AAAAB3NzaC1yc2EAAAABIwAAAQEA5EB5p/5Hp3hGW1oHok+PIOH9Pbn7cnUiGmUEBrCVjnAw+HrKyN8bYVV0dIGllswYXwkG/+bgiBlE6IVIBAq+JwVWu1Sss3KarHY3OvFJUXZoZyRRg/Gc/+LRCE7lyKpwWQ70dbelGRyyJFH36eNv6ySXoUYtGkwlU5IVaHPApOxe4LHPZa/qhSRbPo2hwoh0orCtgejRebNtW5nlx00DNFgsvn8Svz2cIYLxsPVzKgUxs8Zxsxgn+Q/UvR7uq4AbAhyBMLxv7DjJ1pc7PJocuTno2Rw9uMZi1gkjbnmiOh6TTXIEWbnroyIhwc8555uto9melEUmWNQ+C+PwAK+MPw==";

        # A consistent dump, not a copy of a running data directory. immich is
        # the only real user of this postgres, and its database is the index
        # for the 40 GB of photos backed up alongside it — restoring the blobs
        # without it gives you files nothing can find.
        services.postgresqlBackup = lib.mkIf cfg.postgresDump {
          enable = true;
          backupAll = true;
          location = pgBackupDir;
          # Half an hour before restic, which is comfortably longer than a
          # 146 MB dump takes and keeps the two off each other's IO.
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
              # restic's cache. Not strictly required — it rebuilds — but
              # rebuilding it means re-reading index files from the far end, and
              # on a nightly job that is a slow first run every single night.
              directory = "/var/cache/restic-backups-stardust";
              user = "root";
              group = "root";
              mode = "0700";
            }
          ];

        services.restic.backups.stardust = {
          inherit (cfg) repository paths exclude;

          passwordFile = config.sops.secrets."keys/stardust/password".path;
          initialize = true;

          # restic shells out to ssh for the sftp backend, so this is where the
          # key and the port live. -s sftp rather than a shell: the box runs
          # mod_sftp and has no shell to give.
          extraOptions = [
            "sftp.command='${lib.getExe pkgs.openssh} -p 22 -i ${sshKey} -o BatchMode=yes u649268@u649268.your-storagebox.de -s sftp'"
          ];

          timerConfig = {
            OnCalendar = cfg.schedule;
            # Unlike the transcode timer, this one is Persistent. A missed
            # transcode should be skipped; a missed backup should be caught up
            # at the next opportunity, because the gap it leaves is permanent.
            Persistent = true;
            RandomizedDelaySec = "20m";
          };

          pruneOpts = cfg.retention;

          # Reads structure, not just checksums, on 5% of the data per run.
          # A backup that has never been verified is a belief; this is the
          # cheapest way to keep it a fact between full restore tests.
          checkOpts = ["--read-data-subset=5%"];
          runCheck = true;

          # See quiesceServices. Cleanup runs whether the backup succeeded or
          # not, which is the whole reason the stop lives here rather than in a
          # wrapper — a failed run must not leave the unit down until morning.
          # null rather than "" when the list is empty: the option is nullOr str
          # and an empty string still counts as "set", which would have the
          # module write out a no-op script and wire an ExecStopPost for it.
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
