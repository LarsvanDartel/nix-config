# services.smartd — tell me which disk is dying before it dies.
#
# SMART monitoring for endeavour's nine disks (two raidz1 vdevs, hot spare
# wwn-0x5000cca02f3cabb0 pulled in by ZFS on fault). Host-local, not in
# roles.server: gaia's disk is virtual and pioneer's is an SD card — no SMART
# on either. Notifications go to ntfy via smartd's run-a-program mail hook
# rather than a mail stack.
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
      # Also declared by core.notify-failure (identical definitions merge);
      # repeating it keeps this aspect working on a host without a notifier.
      sops.secrets."keys/ntfy/password".sopsFile =
        builtins.toString inputs.nix-secrets + "/hosts/common/secrets.yaml";

      # The module runs the daemon from the store and omits `smartctl` from
      # PATH — the tool you want the moment an alert arrives.
      environment.systemPackages = [pkgs.smartmontools];

      services.smartd = {
        enable = true;

        # Explicit list only: DEVICESCAN would also pick up the BD-RE drive
        # and any USB stick plugged in at boot — alerts about nothing.
        autodetect = false;

        devices =
          map (device: {
            inherit device;
            options = "${cfg.deviceOptions} ${cfg.selfTest}";
          })
          cfg.devices;

        # The mailer is curl; sender/recipient are required by the module and
        # discarded by the script.
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
