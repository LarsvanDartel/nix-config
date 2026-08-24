# core.reboot-required — say so when the running kernel is not the built one.
#
# comin activates a new system within five minutes of `deploy` moving, but
# `switch` only replaces userspace: the kernel, initrd and modules that are
# already running keep running until someone reboots. Nothing in this repo ever
# reboots anything — there is no system.autoUpgrade, no reboot window, and comin
# exposes no reboot option — so a kernel security fix lands in the store, is
# activated, and then sits there indefinitely. endeavour ran for over two months
# that way.
#
# This does NOT reboot. comin has no magic rollback (services/comin.nix), so a
# kernel that does not come back needs the bootloader — IPMI on endeavour, the
# provider console on gaia, and a keyboard on pioneer. Rebooting two production
# hosts unattended on an upstream bump is a worse failure than a stale kernel.
# So it notifies and leaves the decision to a human.
#
# It nags, on purpose. The condition persists until acted on, and a reminder
# that fires once is a reminder that is missed once.
{den, ...}: {
  den.aspects.core.reboot-required = {
    # For the ntfy url/topic/user options and the keys/ntfy/password secret,
    # which are declared there. Reusing them keeps one notification identity for
    # the fleet rather than a second copy to keep in step.
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
            # Not at the same instant on every host, and not at the same
            # instant as the backup.
            RandomizedDelaySec = "30m";
            Persistent = true;
          };
        };
      };
    };
  };
}
