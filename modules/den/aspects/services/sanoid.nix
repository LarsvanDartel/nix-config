# services.sanoid — automatic ZFS snapshots on the array.
#
# sanoid ignores com.sun:auto-snapshot (set in disko.nix), hence its own list.
# Root is btrfs, so the SSD databases are outside this pool: restic is their
# only copy.
#
# `zfs allow tank` printing nothing after a run is normal: the DynamicUser is
# granted permissions in ExecStartPre and revoked in ExecStopPost.
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
            "tank/media" = {
              hourly = 24;
              daily = 14;
              monthly = 3;
            };
            # Own dataset because `tank` itself is not snapshotted.
            "tank/git" = {
              hourly = 48;
              daily = 30;
              monthly = 6;
            };
            "tank/minecraft" = {
              hourly = 48;
              daily = 30;
              monthly = 6;
            };
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
              # autoprune without autosnap would expire snapshots nothing creates.
              autosnap = true;
              autoprune = true;

              # `recursive` on tank/media would silently pick up future children.
              recursive = false;
            })
          cfg.datasets;
        };
      };
    };
  };
}
