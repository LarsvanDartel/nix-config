# services.zed — make the ZFS event daemon actually say something.
#
# zfs-zed.service has been running on endeavour this whole time, from the
# upstream unit, doing nothing useful: ZED_EMAIL_ADDR is unset, so
# zed-functions.sh returns early from every notification path it is asked to
# take. Checksum errors, a vdev degrading, a scrub finding damage — all of it
# reached /etc/zfs/zed.d, found no way to tell anyone, and went to syslog.
#
# This is deliberately not redundant with what already exists, and the seam
# matters:
#
#   prometheus  ZfsPoolUnhealthy watches node_zfs_zpool_state, which only
#               changes once a pool is ALREADY degraded. It is the alarm for
#               "you have lost your redundancy".
#   zed         fires on the individual events that precede that — a disk
#               throwing checksum errors, a scrub repairing blocks, the hot
#               spare being pulled in. It is the alarm for "you are about to".
#   smartd      the disk's own opinion of itself, before ZFS notices anything.
#
# Three layers because a raidz1 vdev tolerates exactly one dead disk, and the
# gap between "degraded" and "dead" is where every recoverable outcome lives.
#
# Routed to ntfy through ZED_EMAIL_PROG rather than a real mail stack. ZED's
# email path is "run this program with the message on stdin"; pointing it at
# curl uses the hook as intended and costs nothing, where the alternative is
# a sendmail wrapper and an SMTP credential that exist to be immediately
# thrown away. Note nixpkgs' `services.zfs.zed.enableMail` is left OFF on
# purpose — it asserts that a setuid sendmail wrapper exists, which is exactly
# the thing being avoided; the three settings it would have written are set
# here directly.
{inputs, ...}: {
  den.aspects.services.zed.nixos = {
    config,
    lib,
    pkgs,
    ...
  }: let
    inherit (lib.options) mkOption;
    inherit (lib.types) bool;

    cfg = config.cosmos.services.zed;
    notifyCfg = config.cosmos.system.notifyFailure;

    notify = pkgs.writeShellApplication {
      name = "zed-ntfy";
      runtimeInputs = with pkgs; [curl coreutils];
      text = ''
        # Invoked as `zed-ntfy <subject>` — ZED substitutes @SUBJECT@ from
        # ZED_EMAIL_OPTS — with the event body on stdin.
        subject="''${1:-ZFS event}"
        password="$(cat ${config.sops.secrets."keys/ntfy/password".path})"

        body="$(head -c 3000)"

        curl -sS --max-time 20 \
          -u "${notifyCfg.user}:$password" \
          -H "Title: ${config.networking.hostName}: $subject" \
          -H "Priority: high" \
          -H "Tags: floppy_disk" \
          -d "$body" \
          "${notifyCfg.url}/${notifyCfg.topic}"
      '';
    };
  in {
    options.cosmos.services.zed = {
      notifyVerbose = mkOption {
        type = bool;
        default = false;
        description = ''
          Notify on *every* scrub and resilver finish, not just the ones that
          found something.

          Off, and this is the noise dial. The scrub runs on the 1st and 15th
          and has never found an error; two guaranteed "everything is fine"
          pushes a month is how an alert channel becomes something you swipe
          away without reading, which then costs you the one that mattered.
          The scrub completing cleanly is already visible in Grafana.
        '';
      };
    };

    config = {
      sops.secrets."keys/ntfy/password".sopsFile =
        builtins.toString inputs.nix-secrets + "/hosts/common/secrets.yaml";

      services.zfs.zed.settings = {
        # zed-functions.sh returns early unless an address is set; it is only
        # ever passed through to the program below, which ignores it.
        ZED_EMAIL_ADDR = "ntfy";
        ZED_EMAIL_PROG = lib.getExe notify;
        ZED_EMAIL_OPTS = "@SUBJECT@";

        ZED_NOTIFY_VERBOSE = cfg.notifyVerbose;

        # Report data corruption ZFS could not repair. This is the event that
        # means a file is actually gone, and the only one where the answer is
        # "restore from restic" rather than "replace a disk".
        ZED_NOTIFY_DATA = true;

        # Pull the hot spare in automatically on a fault. The spare has been
        # sitting AVAIL since the pool was built and nothing was configured to
        # ever use it — a spare that requires a human to notice and act is not
        # meaningfully different from an empty bay.
        ZED_SPARE_ON_CHECKSUM_ERRORS = 10;
        ZED_SPARE_ON_IO_ERRORS = 1;

        # No ZED_USE_ENCLOSURE_LEDS: these are SAS disks behind an HBA in a
        # Dell R7910 backplane, and the enclosure LED path is not wired up
        # here. Setting it produces errors in the journal on every event.
      };
    };
  };
}
