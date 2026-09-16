# core.nix — nix daemon settings. allowUnfree lives in core.nixpkgs.
#
# Nothing collected the store before this: generations are GC roots pinning
# every input of every rebuild, and endeavour had 318 of them (86G of a 233G
# disk). Both a timer and a pressure valve: the timer bounds the rollback
# list, min-free/max-free fires mid-build — a weekly timer alone still lets
# one large build fill the disk.
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

      # No `nix.optimise.automatic`, deliberately: auto-optimise-store already
      # hard-links identical files on write; the timer would be a weekly
      # full-store scan that can only re-find what the write path deduplicated.
      nix.gc = {
        # Not on voyager: desktop/nh.nix sets programs.nh.clean and the nh
        # module asserts clean.enable -> !nix.gc.automatic — two collectors on
        # one store is a build failure. nh's cleaner is also the better one
        # there (it understands home-manager profiles); this covers the servers.
        automatic = !config.programs.nh.clean.enable;
        dates = cfg.gcDates;
        options = "--delete-older-than ${cfg.gcOlderThan}";

        # Spread collections: voyager cross-builds for pioneer and endeavour
        # serves the cache; overlapping collections would slow every deploy.
        randomizedDelaySec = "45min";
      };
    };
  };
}
