# core.nix aspect — nix daemon settings (was flake.modules.nixos.common in
# modules/nixos/system/nix.nix). allowUnfree lives in core.nixpkgs.
#
# Nothing collected the store before this. Every host kept every system
# generation it had ever built, forever, because `nix-collect-garbage` only
# runs when someone types it and nobody was typing it:
#
#   endeavour  318 generations, 31k store paths, 86G of a 233G disk
#   voyager    22 generations
#   pioneer    11 generations, but 85% of a 15G SD card
#
# endeavour is the case this exists for. A generation is not just the closure
# that changed — it is a GC root pinning every input of every rebuild since
# June, which is why a host that deploys often accumulates faster than one that
# does not.
#
# Both a timer and a pressure valve, because they answer different questions.
# The timer bounds how far back the rollback list goes; min-free/max-free bounds
# how close to full the disk gets, and fires during a build rather than after
# it. A weekly timer alone still lets one large build fill the disk on a
# Tuesday.
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

      # No `nix.optimise.automatic` here, deliberately. That timer exists for
      # stores built without `auto-optimise-store`, which hard-links identical
      # files as they are added — already on above. Running both means a weekly
      # full-store scan that can only ever find what the write path already
      # deduplicated, and on endeavour that is 31k paths of pointless IO.
      nix.gc = {
        # Not on voyager. desktop/nh.nix sets `programs.nh.clean.enable` with
        # `--keep-since 4d --keep 3`, and the nh module asserts
        # `clean.enable -> !nix.gc.automatic` — two collectors on one store is
        # a conflict it refuses to build rather than resolve. nh's cleaner is
        # the better one on a laptop anyway: it understands home-manager
        # profiles, which nix.gc does not. So this covers the three servers,
        # which had nothing, and leaves the one host that was already handled
        # alone.
        automatic = !config.programs.nh.clean.enable;
        dates = cfg.gcDates;
        options = "--delete-older-than ${cfg.gcOlderThan}";

        # Every host would otherwise collect at exactly midnight-plus-zero on
        # the same weekday. voyager builds for pioneer under emulation and
        # endeavour serves the cache, so overlapping collections are the one
        # arrangement guaranteed to make a deploy slow.
        randomizedDelaySec = "45min";
      };
    };
  };
}
