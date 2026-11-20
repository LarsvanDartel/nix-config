# core.notify-failure — push a notification when any systemd service fails.
{inputs, ...}: {
  den.aspects.core.notify-failure.nixos = {
    config,
    lib,
    pkgs,
    ...
  }: let
    inherit (lib.options) mkOption mkEnableOption;
    inherit (lib.types) int;
    inherit (lib.modules) mkIf;

    cfg = config.cosmos.system.notifyFailure;

    notify = pkgs.writeShellApplication {
      name = "notify-failure";
      runtimeInputs = with pkgs; [curl systemd coreutils];
      text = ''
        unit="''${1:?usage: notify-failure <unit>}"

        # OnFailure= fires before the unit's own Restart= brings it back; alert only if still failed after the settle.
        sleep ${toString cfg.settleSeconds}
        if ! systemctl is-failed --quiet "$unit"; then
          echo "$unit recovered on its own; not notifying"
          exit 0
        fi

        password="$(cat "$CREDENTIALS_DIRECTORY/ntfy-password")"

        # `|| true` is load-bearing: systemctl status exits 3 for every failed unit, and the script runs under set -e.
        body="$( { systemctl status --no-pager --lines=15 "$unit" || true; } 2>&1 | head -c 3000 )"

        # Retry: failures correlate with network trouble, so the first POST is the likeliest to fail.
        # --retry-all-errors makes curl retry connect failures and timeouts; --retry-max-time bounds it.
        curl -sS --max-time 20 \
          --retry 5 --retry-all-errors --retry-delay 20 --retry-max-time 300 \
          -u "${cfg.user}:$password" \
          -H "Title: ${config.networking.hostName}: $unit failed" \
          -H "Priority: high" \
          -H "Tags: rotating_light" \
          -d "$body" \
          "${cfg.url}/${cfg.topic}"
      '';
    };
  in {
    options.cosmos.system.notifyFailure = {
      enable =
        mkEnableOption "a push notification whenever a systemd service fails"
        // {default = true;};

      settleSeconds = mkOption {
        type = int;
        default = 90;
        description = ''
          How long to wait before deciding a failed unit is really down.

          Trades alert latency for accuracy. Raise it on a host whose services
          use a long RestartSec; lowering it below the longest RestartSec on
          the host reintroduces the false alarms this exists to stop.
        '';
      };
    };

    config = mkIf cfg.enable {
      # Every host publishes as the same user: one secret encrypted to all
      # four host keys rather than four copies to keep in step.
      sops.secrets."keys/ntfy/password".sopsFile =
        builtins.toString inputs.nix-secrets + "/hosts/common/secrets.yaml";

      systemd.services."notify-failure@" = {
        description = "Report that %i failed";
        serviceConfig = {
          Type = "oneshot";
          ExecStart = "${lib.getExe notify} %i";
          LoadCredential = "ntfy-password:${config.sops.secrets."keys/ntfy/password".path}";

          # Oneshot has no start timeout otherwise; sized to the settle wait plus the retry budget.
          TimeoutStartSec = "10min";

          DynamicUser = true;
          CapabilityBoundingSet = [""];
          LockPersonality = true;
          NoNewPrivileges = true;
          PrivateDevices = true;
          PrivateTmp = true;
          ProtectClock = true;
          ProtectControlGroups = true;
          ProtectHome = true;
          ProtectHostname = true;
          ProtectKernelLogs = true;
          ProtectKernelModules = true;
          ProtectKernelTunables = true;
          ProtectSystem = "strict";
          RestrictAddressFamilies = ["AF_INET" "AF_INET6" "AF_UNIX"];
          RestrictNamespaces = true;
          RestrictRealtime = true;
          RestrictSUIDSGID = true;
          SystemCallArchitectures = "native";
          SystemCallFilter = ["@system-service" "~@privileged"];
        };
      };

      # One type-wide drop-in shipped as a package (generateUnits lndirs it into /etc/systemd/system);
      # mapping over config.systemd.services instead recurses infinitely.
      systemd.packages = [
        (pkgs.runCommand "notify-failure-dropins" {} ''
          d=$out/lib/systemd/system

          mkdir -p $d/service.d
          cat > $d/service.d/50-notify-failure.conf <<'EOF'
          [Unit]
          OnFailure=notify-failure@%n.service
          EOF

          # Recursion guard: only a unit-specific drop-in lands after the type-wide one; an empty OnFailure= resets it.
          # Verify: systemctl show notify-failure@x.service -p OnFailure
          mkdir -p "$d/notify-failure@.service.d"
          cat > "$d/notify-failure@.service.d/10-no-recursion.conf" <<'EOF'
          [Unit]
          OnFailure=
          EOF

          sed -i 's/^ *//' $d/service.d/*.conf "$d/notify-failure@.service.d"/*.conf
        '')
      ];
    };
  };
}
