# services.deploy-drift — export the head of nix-config's main from the knot's
# own repository, so prometheus can name the hosts running anything else
# (DeployBehind in services/prometheus.nix). Only on the knot host: it reads
# the bare repository on disk rather than fetching over the published path.
{den, ...}: {
  den.aspects.services.deploy-drift = {
    includes = [den.aspects.services.node-exporter];

    nixos = {
      config,
      lib,
      pkgs,
      ...
    }: let
      inherit (lib.options) mkOption;
      inherit (lib.types) str;

      cfg = config.cosmos.services.deploy-drift;
      stateDir = "/var/lib/deploy-drift";

      export = pkgs.writeShellApplication {
        name = "deploy-drift";
        runtimeInputs = with pkgs; [git coreutils];
        text = ''
          rev="$(git --git-dir=${cfg.repository} rev-parse --verify "refs/heads/${cfg.branch}^{commit}")"

          # Renamed into place: node_exporter must never read half a file, and
          # it skips anything not ending in .prom.
          cat >${stateDir}/main.prom.tmp <<EOF
          # HELP nix_config_main_info The commit at the head of nix-config's ${cfg.branch} on the knot.
          # TYPE nix_config_main_info gauge
          nix_config_main_info{revision="$rev"} 1
          EOF
          mv ${stateDir}/main.prom.tmp ${stateDir}/main.prom
          echo "${cfg.branch} at $rev"
        '';
      };
    in {
      options.cosmos.services.deploy-drift = {
        repository = mkOption {
          type = str;
          example = "/tank/knot/repos/plc/ab/cdef…";
          description = "nix-config's bare repository on the knot's disk.";
        };

        branch = mkOption {
          type = str;
          default = "main";
          description = "The branch every host is expected to run.";
        };
      };

      config = {
        services.prometheus.exporters.node.extraFlags = ["--collector.textfile.directory=${stateDir}"];

        systemd.services.deploy-drift = {
          description = "Export nix-config's ${cfg.branch} head for prometheus";
          serviceConfig = {
            Type = "oneshot";
            ExecStart = lib.getExe export;
            # packed-refs is 0600 knot.
            User = config.services.tangled.knot-rs.user;
            StateDirectory = "deploy-drift";
            StateDirectoryMode = "0755";

            CapabilityBoundingSet = [""];
            NoNewPrivileges = true;
            PrivateNetwork = true;
            PrivateTmp = true;
            ProtectHome = true;
            ProtectSystem = "strict";
          };
        };

        systemd.paths.deploy-drift = {
          wantedBy = ["multi-user.target"];
          pathConfig = {
            # A push leaves a loose ref; the knot's repack later moves it into
            # packed-refs and deletes the loose one. PathChanged, not
            # PathModified: git renames a lock file over either.
            PathChanged = [
              "${cfg.repository}/refs/heads/${cfg.branch}"
              "${cfg.repository}/packed-refs"
            ];
            Unit = "deploy-drift.service";
          };
        };

        # The path unit cannot queue a push that lands mid-run, and the state
        # directory is not persisted, so a boot starts without main.prom.
        systemd.timers.deploy-drift = {
          wantedBy = ["timers.target"];
          timerConfig = {
            OnBootSec = "2m";
            OnUnitInactiveSec = "15m";
          };
        };
      };
    };
  };
}
