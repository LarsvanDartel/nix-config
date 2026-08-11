# services.smartd — tell me which disk is dying before it dies.
#
# endeavour has nine disks and no SMART monitoring of any kind: `smartctl` was
# not even installed. Eight of them are second-hand SAS spinners in two raidz1
# vdevs, which means the pool survives losing one disk *per vdev* and no more.
# Without this, the way you learn a disk is failing is that it fails — and if
# the second one in the same vdev is also old and also unmonitored, the way you
# learn about that is losing the pool.
#
# There is a hot spare (wwn-0x5000cca02f3cabb0) sitting AVAIL. ZFS will pull it
# in automatically on a fault, which is exactly the event that is currently
# invisible: the pool would silently drop from "redundant with a spare" to
# "redundant" and nothing would say so.
#
# Not in roles.server, and not on the other two hosts, because SMART is a
# property of real disks:
#
#   gaia     one QEMU virtual disk. smartctl reports the hypervisor's fiction.
#   pioneer  an SD card on the mmc bus, which has no SMART interface at all —
#            eMMC health lives in ext_csd, not here.
#
# A monitor that reports nothing useful on two of three hosts does not belong
# in the role; it belongs on the host with the disks. Same reasoning that keeps
# core.notify-failure out of roles.default.
#
# Notifications go to ntfy through the mail hook rather than a mail stack.
# smartd's only notification mechanism is "run a program with the message on
# stdin", which is what a mailer is; pointing that at curl is using the hook
# as designed, not subverting it.
{inputs, ...}: {
  den.aspects.services.smartd.nixos = {
    config,
    lib,
    pkgs,
    ...
  }: let
    inherit (lib.options) mkOption;
    inherit (lib.types) str listOf;

    cfg = config.cosmos.services.smartd;
    notifyCfg = config.cosmos.system.notifyFailure;

    # Reads the message smartd would have mailed and posts it instead. Runs as
    # root, from smartd, so it can read the sops secret directly — unlike
    # notify-failure@, which is DynamicUser and needs LoadCredential.
    notify = pkgs.writeShellApplication {
      name = "smartd-ntfy";
      runtimeInputs = with pkgs; [curl coreutils];
      text = ''
        # smartd invokes this the way it would invoke a mailer: the body
        # arrives on stdin and the useful summary is in the environment. The
        # `-i "$recipient"` argument sendmail would take is accepted and
        # ignored.
        password="$(cat ${config.sops.secrets."keys/ntfy/password".path})"

        # SMARTD_MESSAGE is the one-line verdict; stdin is that plus the full
        # `smartctl -a` dump the module appends. Truncated for the same reason
        # notify-failure trims the journal — ntfy renders a phone notification,
        # and 200 lines of SMART attributes is not one.
        body="$(printf '%s\n\n%s' "''${SMARTD_MESSAGE:-}" "$(cat)" | head -c 3000)"

        curl -sS --max-time 20 \
          -u "${notifyCfg.user}:$password" \
          -H "Title: ${config.networking.hostName}: SMART on ''${SMARTD_DEVICESTRING:-a disk}" \
          -H "Priority: urgent" \
          -H "Tags: floppy_disk,rotating_light" \
          -d "$body" \
          "${notifyCfg.url}/${notifyCfg.topic}"
      '';
    };
  in {
    options.cosmos.services.smartd = {
      devices = mkOption {
        type = listOf str;
        default = lib.mapAttrsToList (_: d: d.device) config.disko.devices.disk;
        defaultText = "every disk disko knows about";
        description = ''
          Devices to monitor, as stable /dev/disk/by-id paths.

          Derived from `disko.devices.disk` rather than written out again. The
          same nine wwn identifiers already appear in _hw/endeavour/disko.nix;
          a second hand-maintained copy is a list that drifts the first time a
          disk is replaced, and the failure mode of drift here is a disk that
          silently stops being watched. sdX letters are not stable across boots
          and are never used.
        '';
      };

      deviceOptions = mkOption {
        type = str;
        default = "-a -n standby,10,q";
        description = ''
          Per-device smartd directives.

          Deliberately *not* nixpkgs' default of `-a -o on -S on -n
          standby,10,q`. `-o`/`-S` toggle SATA offline-test and
          attribute-autosave, which have no SCSI equivalent — every disk here
          except the system SSD reports over the SAS bus and would reject them.

          No `-d` either: smartctl's auto-detection resolves these correctly
          through the HBA. If a device ever comes back "Unknown USB bridge" or
          similar, add `-d scsi` here rather than guessing per device.
        '';
      };

      selfTest = mkOption {
        type = str;
        default = "-s (S/../.././05|L/../../6/06)";
        description = ''
          Self-test schedule: short daily at 05:00, long on Saturdays at 06:00.

          Chosen to miss everything else that touches these disks — restic at
          02:00, the scrub at 02:30 on the 1st and 15th, and the AV1 transcode
          from 03:00. A long test on eight spinners is hours of seeking; run it
          against a scrub and both take longer while playback stutters.
        '';
      };
    };

    config = {
      # Also declared by core.notify-failure, which this host has via
      # roles.server. Identical definitions merge; repeating it means this
      # aspect is not silently broken if it is ever used somewhere that has no
      # failure notifier.
      sops.secrets."keys/ntfy/password".sopsFile =
        builtins.toString inputs.nix-secrets + "/hosts/common/secrets.yaml";

      services.smartd = {
        enable = true;

        # Explicit list only. DEVICESCAN would also pick up the BD-RE drive and
        # any USB stick that happens to be plugged in at boot, and each of those
        # is a source of alerts about nothing.
        autodetect = false;

        devices =
          map (device: {
            inherit device;
            options = "${cfg.deviceOptions} ${cfg.selfTest}";
          })
          cfg.devices;

        # The mail path is the hook; the mailer is curl. sender/recipient are
        # required by the module and land in headers this script discards.
        notifications.mail = {
          enable = true;
          sender = "smartd@${config.networking.hostName}";
          recipient = "ntfy";
          mailer = lib.getExe notify;
        };
      };
    };
  };
}
