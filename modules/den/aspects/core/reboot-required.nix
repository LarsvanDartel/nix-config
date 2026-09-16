# core.reboot-required — say so when the running kernel is not the built one.
# comin's switch replaces userspace only — kernel/initrd/modules keep running
# until a reboot, and nothing here reboots (no autoUpgrade, no reboot window,
# no comin reboot option). This does NOT reboot either: comin has no magic
# rollback (services/comin.nix), so a kernel that does not come back needs the
# console — IPMI on endeavour, provider console on gaia, keyboard on pioneer.
# It nags on purpose: the condition persists until acted on.
{den, ...}: {
  den.aspects.core.reboot-required = {
    # For the ntfy options and the keys/ntfy/password secret, keeping one
    # notification identity for the fleet.
    includes = [den.aspects.core.notify-failure];

    nixos = {
      config,
      lib,
      pkgs,
      ...
    }: let
      inherit (lib.options) mkOption mkEnableOption;
      inherit (lib.types) str;
      inherit (lib.modules) mkIf;

      cfg = config.cosmos.system.rebootRequired;
      notifyCfg = config.cosmos.system.notifyFailure;

      check = pkgs.writeShellApplication {
        name = "reboot-required-check";
        runtimeInputs = with pkgs; [curl coreutils];
        text = ''
          # The three things a reboot actually changes. Comparing the whole
          # system path would fire on every activation, which is daily here
          # thanks to flake-bump and says nothing about the kernel.
          changed=""
          for part in kernel initrd kernel-modules; do
            booted="$(readlink -f "/run/booted-system/$part" 2>/dev/null || true)"
            current="$(readlink -f "/run/current-system/$part" 2>/dev/null || true)"
            if [ "$booted" != "$current" ]; then
              changed="$changed $part"
            fi
          done

          if [ -z "$changed" ]; then
            echo "running kernel matches the current system; nothing to do"
            exit 0
          fi

          echo "reboot required, differs in:$changed"

          # Read out of the store path, not /run/*/kernel-version: that file
          # does not exist on these hosts (checked), and reading it would have
          # made both versions "unknown" in every notification this ever sends.
          # `.../<hash>-linux-6.18.44/bzImage` -> `6.18.44`.
          kver() {
            basename "$(dirname "$(readlink -f "$1" 2>/dev/null)")" |
              sed 's/.*-linux-//' || echo unknown
          }
          booted_ver="$(kver /run/booted-system/kernel)"
          current_ver="$(kver /run/current-system/kernel)"

          password="$(cat "$CREDENTIALS_DIRECTORY/ntfy-password")"

          # --max-time so a hung edge cannot wedge the unit. One attempt: this
          # runs again tomorrow, so a retry storm buys nothing.
          curl -sS --max-time 20 \
            -u "${notifyCfg.user}:$password" \
            -H "Title: ${config.networking.hostName}: reboot required" \
            -H "Priority: default" \
            -H "Tags: arrows_counterclockwise" \
            -d "Running $booted_ver, built $current_ver (differs in:$changed).

          Reboot when convenient. There is no automatic rollback, so prefer a
          time when the console is reachable." \
            "${notifyCfg.url}/${notifyCfg.topic}"
        '';
      };
    in {
      options.cosmos.system.rebootRequired = {
        enable =
          mkEnableOption "a push notification while the running kernel is stale"
          // {default = true;};

        interval = mkOption {
          type = str;
          default = "daily";
          description = ''
            OnCalendar for the check. Daily by design: the condition persists
            until someone reboots, and this is the reminder that it is still
            true.
          '';
        };
      };

      config = mkIf (cfg.enable && notifyCfg.enable) {
        systemd.services.reboot-required = {
          description = "Report that the running kernel is not the current one";
          serviceConfig = {
            Type = "oneshot";
            ExecStart = lib.getExe check;
            LoadCredential = "ntfy-password:${config.sops.secrets."keys/ntfy/password".path}";

            # Reads two symlinks and one credential, and talks to ntfy.
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

        systemd.timers.reboot-required = {
          wantedBy = ["timers.target"];
          timerConfig = {
            OnCalendar = cfg.interval;
            # Not at the same instant on every host or as the backup.
            RandomizedDelaySec = "30m";
            Persistent = true;
          };
        };
      };
    };
  };
}
