# core.journald — bound the journal.
#
# Nothing set `services.journald.*` before this, so every host ran on the
# nixpkgs default of "10% of the filesystem, capped at 4G" and nothing else.
# That is a sizing rule for a machine whose disk exists to hold logs, and it
# went unnoticed because journald evicts silently rather than filling the disk:
#
#   gaia      3.7G of journal on a 38G disk
#   pioneer   575M with 1.7G free on an 89%-full SD card
#   endeavour 767M
#
# So the defaults were not merely generous, they were actively costing gaia a
# tenth of its disk and pioneer a third of its remaining space.
#
# Bounded by *time* as well as size. Size alone answers "how much disk will
# this cost" but not "how far back can I look", and the second question is the
# one being asked when something broke last Tuesday. Whichever limit is hit
# first wins.
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

    config.services.journald.extraConfig = ''
      SystemMaxUse=${cfg.maxUse}
      MaxRetentionSec=${cfg.maxRetention}
      MaxFileSec=${cfg.maxFileSec}
    '';

    # Rate limiting is deliberately left at the default (10000 entries per 30s
    # per service). The loudest thing in the fleet is ipmi-fancontrol, which
    # logs a sensor line every 10s on endeavour — six a minute, four orders of
    # magnitude under the limit. Nothing here is chatty enough to warrant it,
    # and a rate limit that ever engages drops exactly the burst of lines a
    # crash produces, which is the moment the log matters most.
  };
}
