# core.nix — nix daemon settings + store GC (timer and min-free/max-free).
{...}: {
  den.aspects.core.nix.nixos = {
    config,
    lib,
    ...
  }: let
    inherit (lib.options) mkOption;
    inherit (lib.types) str ints;

    cfg = config.cosmos.system.nix;
  in {
    options.cosmos.system.nix = {
      gcDates = mkOption {
        type = str;
        default = "weekly";
        description = ''
          OnCalendar for the garbage collector, as `nix.gc.dates`.

          Weekly rather than daily: a collect that runs more often than you
          deploy spends its time walking the store to find nothing, and the
          walk is the expensive part on spinning disks and SD cards alike.
        '';
      };

      gcOlderThan = mkOption {
        type = str;
        default = "30d";
        description = ''
          How much rollback history to keep, as the argument to
          `--delete-older-than`.

          This is the real cost/benefit dial: it is exactly "how far back can I
          boot into a working system", and a month covers the window in which
          anyone notices a regression. Shorten it on hosts where the store is a
          meaningful fraction of the disk.
        '';
      };

      minFree = mkOption {
        type = ints.positive;
        default = 1024 * 1024 * 1024;
        description = ''
          Free bytes below which the daemon starts collecting mid-build, as
          `nix.settings.min-free`.

          Sized per host: this must sit far enough above zero that a build can
          finish after the collection, but far enough below the disk size that
          it is not permanently engaged. A value larger than the host's usual
          free space means the daemon collects constantly and never wins.
        '';
      };

      maxFree = mkOption {
        type = ints.positive;
        default = 5 * 1024 * 1024 * 1024;
        description = ''
          Free bytes at which mid-build collection stops, as
          `nix.settings.max-free`. Must exceed minFree; the gap is how much
          work each triggered collection does, so a narrow gap means collecting
          often and a wide one means a long pause.
        '';
      };
    };

    config = {
      nix.settings = {
        trusted-users = ["@wheel" "root"];
        auto-optimise-store = lib.mkDefault true;
        use-xdg-base-directories = true;
        experimental-features = ["nix-command" "flakes"];
        warn-dirty = false;

        min-free = cfg.minFree;
        max-free = cfg.maxFree;
      };

      # No `nix.optimise.automatic`: auto-optimise-store already dedups on write.
      nix.gc = {
        # nh module asserts clean.enable -> !nix.gc.automatic; two collectors
        # on one store is a build failure.
        automatic = !config.programs.nh.clean.enable;
        dates = cfg.gcDates;
        options = "--delete-older-than ${cfg.gcOlderThan}";

        # Spread collections so they don't overlap deploys/cache serving.
        randomizedDelaySec = "45min";
      };
    };
  };
}
