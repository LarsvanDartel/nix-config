# services.sanoid — automatic ZFS snapshots on the array.
#
# The mechanism for the auto-snapshot property `_hw/endeavour/disko.nix` has
# set on tank/encrypted/main since the pool was created while nothing ever
# read it — sanoid does not consult com.sun:auto-snapshot, hence its own
# dataset list.
#
# Covers deleted files, misrenames, bad transcodes (instant local rollback).
# Does NOT cover pool death, fire or ransomware with root — that is restic's
# job. Scope limit: the root filesystem is btrfs, so every database on the
# SSD (postgres/immich, kanidm, traccar, arr SQLite, grafana) is outside this
# pool; for those, restic is the only copy.
#
# The delegation looks broken twice over and is not: the module's DynamicUser
# `sanoid` is granted snapshot,mount,destroy in ExecStartPre and revoked in
# ExecStopPost, so `zfs allow tank` prints nothing after a run, and the user
# only exists while the unit is active.
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
            # 40 GB of immich originals under /tank/media/library/images/upload;
            # the library itself is 700 GB the arr stack could re-acquire, but
            # slowly.
            "tank/media" = {
              hourly = 24;
              daily = 14;
              monthly = 3;
            };
            # The knot's repositories — a dataset of their own because `tank`
            # itself is not snapshotted (see below), so a directory there would
            # get no coverage. Also in restic; a regretted force-push is noticed
            # in minutes, not months.
            "tank/git" = {
              hourly = 48;
              daily = 30;
              monthly = 6;
            };
            # Minecraft worlds — the rollback that actually gets used (creeper
            # in spawn, bad WorldEdit, insider griefer; all noticed within the
            # hour). Also in restic: the fast path, not the last copy.
            "tank/minecraft" = {
              hourly = 48;
              daily = 30;
              monthly = 6;
            };
            # Empty today, but the encrypted dataset: whatever lands here was
            # worth encrypting, so it gets the long tail.
            "tank/encrypted/main" = {
              hourly = 12;
              daily = 30;
              monthly = 6;
            };
          };
          description = ''
            Datasets to snapshot, mapped to how long each period is kept.

            These are **durations, not counts**, which is the single easiest
            thing to misread here. sanoid prunes on a snapshot's real ctime
            against `now - value * period` (sanoid line 354), so `hourly = 24`
            means "keep hourly snapshots for 24 hours", not "keep 24 of them".
            The two coincide only while snapshots are actually taken once per
            period; take them more often and you keep more than the number
            suggests, less often and you keep fewer.

            The practical consequence is that nothing is pruned until a
            snapshot is genuinely older than its window — a fresh deploy looks
            like pruning is broken for the first `hourly` hours, and is not.

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

              # Not recursive: every dataset is named explicitly; `recursive`
              # on tank/media would silently pick up future children.
              recursive = false;
            })
          cfg.datasets;
        };

        # sanoid runs as root and writes no state (snapshots live in pool
        # metadata) — nothing to persist. Alerts via the OnFailure drop-in in
        # core/notify-failure.nix.
      };
    };
  };
}
