# services.zed — make the ZFS event daemon actually say something.
#
# Upstream zfs-zed.service ran silently: ZED_EMAIL_ADDR unset makes
# zed-functions.sh return early from every notification path. Three alarm
# layers by design: prometheus watches pool state (already degraded), zed
# fires on the events that precede it (checksum errors, scrub repairs, spare
# pull-in), smartd is the disk's own opinion. Routed to ntfy via ZED_EMAIL_PROG
# — `services.zfs.zed.enableMail` is OFF on purpose: it asserts a setuid
# sendmail wrapper exists, the thing being avoided.
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

        # Corruption ZFS could not repair — the one event whose answer is
        # "restore from restic" rather than "replace a disk".
        ZED_NOTIFY_DATA = true;

        # Auto-pull the hot spare on fault: a spare that needs a human to
        # notice and act is an empty bay.
        ZED_SPARE_ON_CHECKSUM_ERRORS = 10;
        ZED_SPARE_ON_IO_ERRORS = 1;

        # No ZED_USE_ENCLOSURE_LEDS: the enclosure LED path is unwired for
        # these SAS disks behind the HBA; setting it errors in the journal on
        # every event.
      };
    };
  };
}
