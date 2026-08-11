# services.sanoid — automatic ZFS snapshots on the array.
#
# `_hw/endeavour/disko.nix` has set `com.sun:auto-snapshot = "true"` on
# tank/encrypted/main since the pool was created, and nothing has ever read
# that property: `zfs list -t snapshot` returned zero rows. The intent was
# declared, the mechanism was never built. This is the mechanism — and it uses
# sanoid's own dataset list rather than the property, because sanoid does not
# consult com.sun:auto-snapshot at all.
#
# What this protects against, and what it does not:
#
#   * covers  — a deleted file, an arr misrename that walks a whole season into
#     the wrong folder, a bad transcode replacing an original. Rollback is
#     instant and local.
#   * does NOT cover — the pool dying, the machine burning, or ransomware with
#     root. Snapshots live inside the thing they protect. That is restic's job,
#     and the two are deliberately not the same tool.
#
# Scope limit worth stating plainly: **the root filesystem is btrfs**, not ZFS.
# Every database on this host — postgres/immich, kanidm, traccar, the arr
# SQLite files, grafana — sits on the 250 GB SSD, entirely outside this pool.
# sanoid protects /tank and touches none of them. Anyone reading this expecting
# "we have snapshots" to mean "the databases are recoverable" would be wrong;
# for those, restic is the only copy.
#
# Cheap on copy-on-write: a snapshot costs nothing at creation and grows only
# as the live data diverges. On a mostly-append media library that is close to
# free, which is why the retention here is generous.
{...}: {
  den.aspects.services.sanoid = {
    nixos = {
      config,
      lib,
      ...
    }: let
      inherit (lib.options) mkOption;
      inherit (lib.types) attrsOf ints str;

      cfg = config.cosmos.services.sanoid;
    in {
      options.cosmos.services.sanoid = {
        datasets = mkOption {
          type = attrsOf (attrsOf ints.unsigned);
          default = {
            # 40 GB of immich originals live under
            # /tank/media/library/images/upload, and the media library itself
            # is 700 GB the arr stack could re-acquire but would take weeks to.
            "tank/media" = {
              hourly = 24;
              daily = 14;
              monthly = 3;
            };
            # Empty today, but it is the encrypted dataset — whatever ends up
            # here is by definition the stuff that was worth encrypting, so it
            # gets the longer tail.
            "tank/encrypted/main" = {
              hourly = 12;
              daily = 30;
              monthly = 6;
            };
          };
          description = ''
            Datasets to snapshot, mapped to their retention counts.

            Deliberately not `tank` itself. Snapshotting the pool root with
            `recursive` would also snapshot tank/media, and every file would be
            held by two independent retention policies expiring on different
            days — which is how a pool that looks 32% full stops freeing space
            when you delete things.
          '';
        };

        pruneSchedule = mkOption {
          type = str;
          default = "hourly";
          description = ''
            OnCalendar for both sanoid's snapshot and prune runs.

            Hourly is sanoid's intended cadence and the finest granularity the
            retention above asks for. It is a metadata operation on ZFS, not a
            scan, so it does not compete with playback the way the nightly
            transcode does.
          '';
        };
      };

      config = {
        services.sanoid = {
          enable = true;
          interval = cfg.pruneSchedule;

          datasets = lib.mapAttrs (_: retention:
            retention
            // {
              # autoprune without autosnap would expire snapshots nothing is
              # creating; the pair is what makes the retention counts mean
              # anything.
              autosnap = true;
              autoprune = true;

              # Not recursive: every dataset here is named explicitly, and
              # `recursive` on tank/media would pick up any future child
              # dataset silently — including one deliberately created to hold
              # something that should not be snapshotted.
              recursive = false;
            })
          cfg.datasets;
        };

        # sanoid runs as root and writes no state of its own — snapshots live
        # in pool metadata — so there is nothing to persist. Failure
        # notification is automatic via the type-wide OnFailure drop-in in
        # core/notify-failure.nix.
      };
    };
  };
}
