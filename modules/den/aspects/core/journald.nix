# core.journald — bound the journal by size and time; the nixpkgs default
# (10% of the filesystem, capped 4G) was costing pioneer a third of its SD card.
{...}: {
  den.aspects.core.journald.nixos = {
    config,
    lib,
    ...
  }: let
    inherit (lib.options) mkOption;
    inherit (lib.types) str;

    cfg = config.cosmos.system.journald;
  in {
    options.cosmos.system.journald = {
      maxUse = mkOption {
        type = str;
        default = "1G";
        example = "256M";
        description = ''
          Disk the journal may occupy, as SystemMaxUse. Lower it on hosts where
          a gigabyte is a meaningful fraction of the disk — see the per-host
          overrides, which is most of the point of this being an option.
        '';
      };

      maxRetention = mkOption {
        type = str;
        default = "30day";
        description = ''
          Discard entries older than this regardless of how much room is left,
          as MaxRetentionSec. A month is about as far back as anything here is
          worth investigating, and past that the journal is only paying rent.
        '';
      };

      maxFileSec = mkOption {
        type = str;
        default = "7day";
        description = ''
          How often to start a new journal file, as MaxFileSec.

          Retention is enforced by deleting whole files, so this is the real
          granularity of `maxRetention`: with the default one-month files a
          30-day retention can only ever delete something a month old, and the
          journal overshoots its limit for weeks. Weekly files make the cap
          mean roughly what it says.
        '';
      };
    };

    config.services.journald.settings.Journal = {
      SystemMaxUse = cfg.maxUse;
      MaxRetentionSec = cfg.maxRetention;
      MaxFileSec = cfg.maxFileSec;
    };

    # Rate limiting deliberately left at the default: a limit that ever engages
    # drops exactly the burst a crash produces.
  };
}
