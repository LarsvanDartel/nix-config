# services.transcode — periodically re-encode library video to AV1 on the GPU.
#
# Destructive but guarded: every output is probed before replacing anything,
# files that do not shrink by `minSaving` are restored and marked, and each
# night is bounded by `maxPerRun`, `parallel` and free pool space.
{den, ...}: {
  den.aspects.services.transcode = {
    includes = with den.aspects.services; [
      arr
      arr.radarr
      arr.sonarr
    ];

    nixos = {
      config,
      lib,
      pkgs,
      ...
    }: let
      inherit (lib.options) mkOption mkEnableOption;
      inherit (lib.types) listOf str path ints float;

      cfg = config.cosmos.services.transcode;
      arr = config.cosmos.services.arr;

      user = "transcode";
      stateDir = "/var/lib/transcode";

      # Not pkgs.ffmpeg: intel-media-driver 26.1.6 needs libva >= 2.24, which
      # nixpkgs' ffmpeg (libva 2.22) lacks; jellyfin-ffmpeg carries 2.24.
      ffmpeg = pkgs.jellyfin-ffmpeg;

      arrs = [
        {
          name = "radarr";
          kind = "movie";
          url = "http://127.0.0.1:${toString arr.radarr.port}";
          library = "${arr.mediaDir}/library/movies";
        }
        {
          name = "sonarr";
          kind = "series";
          url = "http://127.0.0.1:${toString arr.sonarr.port}";
          library = "${arr.mediaDir}/library/shows";
        }
      ];

      # Underscored so import-tree skips it.
      script = ./_transcode.py;
    in {
      options.cosmos.services.transcode = {
        enable =
          mkEnableOption "periodic re-encoding of the library to AV1"
          // {default = true;};

        dryRun = mkOption {
          type = lib.types.bool;
          default = true;
          description = ''
            List what would be encoded and change nothing.

            On by default because this replaces originals and there is no undo.
            Leave it on for a first deploy, read the candidate list, then turn
            it off.
          '';
        };

        libraries = mkOption {
          type = listOf path;
          default = [
            "${arr.mediaDir}/library/movies"
            "${arr.mediaDir}/library/shows"
          ];
          defaultText = "the radarr and sonarr libraries";
          description = "Directory trees to walk.";
        };

        skipCodecs = mkOption {
          type = listOf str;
          default = ["av1"];
          example = ["av1" "hevc"];
          description = ''
            Source video codecs to leave alone, as ffprobe names them.

            Only "av1" by default, so HEVC is in scope — but AV1 buys little
            over a good HEVC encode and costs a generation of quality, so most
            HEVC files should end up rejected by `minSaving` rather than
            replaced. Add "hevc" here once that is confirmed, and the pointless
            encodes stop being attempted at all.
          '';
        };

        minSizeMiB = mkOption {
          type = ints.positive;
          default = 500;
          description = "Ignore files smaller than this; the risk outweighs the win.";
        };

        quality = mkOption {
          type = ints.positive;
          default = 90;
          description = ''
            global_quality for av1_vaapi under CQP rate control.

            This is an AV1 quantiser index on a 0-255 scale, not a 0-51
            CRF-like one — a value that looks sane for x264 is near-lossless
            here and produces files several times larger than the source.
            Measured on this library at 1080p:

              source                       q:v 90 output
              0.95 Mbit/s x265 (tight)     0.98x  — break-even
              14.3 Mbit/s x264 (Bluray)    0.14x  — 86% smaller

            90 is therefore about as efficient per bit as a good x265 encode:
            it takes the fat h264 encodes apart and leaves already-tight files
            roughly where they were, which is exactly the split `minSaving`
            then acts on. Lower is better quality and bigger; useful range
            here is roughly 70-130.
          '';
        };

        minSaving = mkOption {
          type = float;
          default = 0.15;
          description = ''
            Discard the output unless it is at least this much smaller, as a
            fraction, and record the file so it is not attempted again.

            This is the safety valve on scope: pointed at a library that is
            already efficiently encoded, the job costs GPU time and changes
            nothing, rather than trading quality for no space.
          '';
        };

        maxPerRun = mkOption {
          type = ints.positive;
          default = 4;
          description = "Files to process per run, largest first.";
        };

        parallel = mkOption {
          type = ints.positive;
          default = 1;
          description = ''
            How many files to encode at once.

            The Arc has one encode engine, so this does not multiply encoder
            throughput — what it recovers is the time each job spends *not*
            encoding. A single ffmpeg here runs at roughly six cores of demux,
            filter and hwupload against one GPU, so the engine idles in gaps
            that a second job can fill.

            Every concurrent job also holds a whole second copy of its source
            on the pool until it is renamed into place, so this multiplies the
            transient space requirement — see `minFreeGiB`, which accounts for
            the jobs in flight.

            Keep it low. Past two or three the jobs contend for the same engine
            and the array, and the wall clock stops improving while jellyfin's
            own transcodes get slower.
          '';
        };

        minFreeGiB = mkOption {
          type = ints.positive;
          default = 200;
          description = ''
            Stop when the pool would drop below this. ZFS is copy-on-write, so
            each replacement transiently needs the new file's size on top of
            the old one, and raidz1 fills faster than the numbers suggest.
          '';
        };

        device = mkOption {
          type = path;
          default = "/dev/dri/renderD128";
          description = ''
            The render node to encode on.

            On a host with more than one GPU, set this to the
            `/dev/dri/by-path/pci-<addr>-render` symlink rather than leaving it
            at the default. renderD12x numbering is assigned in probe order, so
            it is not stable across boots: if one card fails to bind, the
            number it used to hold silently moves to another card and the
            encode is attempted on whatever answers. by-path either resolves to
            the card that was meant or does not exist, which is the failure
            worth having.
          '';
        };

        unmonitor = mkOption {
          type = lib.types.bool;
          default = true;
          description = ''
            After replacing a file, unmonitor it in radarr/sonarr and trigger a
            rescan, so the arr records the new file instead of trying to
            re-acquire the original.
          '';
        };

        schedule = mkOption {
          type = str;
          default = "*-*-* 03:00:00";
          description = "OnCalendar expression for the nightly run.";
        };
      };

      config = lib.mkIf cfg.enable {
        cosmos.system.impermanence.persist.directories = [
          {
            directory = stateDir;
            inherit user;
            group = "media";
            mode = "0750";
          }
        ];

        # `media` as the *primary* group, as the arrs do: replaced files must
        # stay writable by them. render/video reach the GPU.
        users.users.${user} = {
          isSystemUser = true;
          group = "media";
          home = stateDir;
          extraGroups = ["render" "video"];
        };

        systemd.services.transcode = {
          description = "Re-encode library video to AV1";
          after = ["network-online.target" "radarr.service" "sonarr.service"];
          # After without wants is an eval warning, fatal under abort-on-warn.
          wants = ["network-online.target"];

          environment = {
            FFMPEG = "${ffmpeg}/bin/ffmpeg";
            FFPROBE = "${ffmpeg}/bin/ffprobe";
            DEVICE = cfg.device;
            LIBRARIES = builtins.toJSON cfg.libraries;
            SKIP_CODECS = builtins.toJSON cfg.skipCodecs;
            ARRS = builtins.toJSON arrs;
            MIN_SIZE_MIB = toString cfg.minSizeMiB;
            MIN_FREE_GIB = toString cfg.minFreeGiB;
            MIN_SAVING = toString cfg.minSaving;
            MAX_PER_RUN = toString cfg.maxPerRun;
            PARALLEL = toString cfg.parallel;
            QUALITY = toString cfg.quality;
            DRY_RUN =
              if cfg.dryRun
              then "1"
              else "0";
            UNMONITOR =
              if cfg.unmonitor
              then "1"
              else "0";
            STATE_FILE = "${stateDir}/state.json";
            PYTHONUNBUFFERED = "1";
          };

          serviceConfig = {
            Type = "oneshot";
            User = user;
            Group = "media";
            ExecStart = "${pkgs.python3}/bin/python ${script}";

            # Read as root by systemd, so no access to the arr state dirs.
            LoadCredential =
              map (a: "${a.name}-config:${arr.stateDir}/${a.name}/config.xml")
              arrs;

            StateDirectory = baseNameOf stateDir;
            WorkingDirectory = stateDir;

            Nice = 19;
            IOSchedulingClass = "idle";

            # PrivateDevices hides /dev/dri and MemoryDenyWriteExecute breaks the
            # GPU userspace, so neither is set.
            DeviceAllow = ["${cfg.device} rw"];
            ProtectSystem = "strict";
            ReadWritePaths = cfg.libraries ++ [stateDir];

            CapabilityBoundingSet = [""];
            LockPersonality = true;
            NoNewPrivileges = true;
            PrivateTmp = true;
            ProtectClock = true;
            ProtectControlGroups = true;
            ProtectHome = true;
            ProtectHostname = true;
            ProtectKernelLogs = true;
            ProtectKernelModules = true;
            ProtectKernelTunables = true;
            ProtectProc = "invisible";
            RestrictAddressFamilies = ["AF_INET" "AF_INET6" "AF_UNIX"];
            RestrictNamespaces = true;
            RestrictRealtime = true;
            RestrictSUIDSGID = true;
            SystemCallArchitectures = "native";
            SystemCallFilter = ["@system-service" "~@privileged"];
          };
        };

        # Not Persistent: a missed night is skipped, not a burst at boot.
        systemd.timers.transcode = {
          description = "Nightly library re-encode";
          wantedBy = ["timers.target"];
          timerConfig = {
            OnCalendar = cfg.schedule;
            RandomizedDelaySec = "30m";
            Persistent = false;
            Unit = "transcode.service";
          };
        };
      };
    };
  };
}
