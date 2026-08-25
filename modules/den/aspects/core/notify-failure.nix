# core.notify-failure — push a notification when any systemd service fails.
#
# The fleet runs ~96 services and nothing watched any of them: a unit that died
# at 3am stayed dead until somebody happened to look. This is the cheapest
# thing that changes that, and it works on every host including pioneer, which
# cannot carry a metrics agent.
#
# Wired to *every* service at once through systemd's type-wide drop-in
# directory. A drop-in in `/etc/systemd/system/service.d/` applies to all units
# whose name ends in `.service` — so one file covers everything that exists now
# and everything added later, with no per-unit boilerplate and nothing to keep
# in sync. The alternative, mapping over `config.systemd.services` to set
# `onFailure` on each, reads the option it is defining and infinitely recurses.
#
# The notifier must not notify about itself. Drop-ins are applied unit file
# first, then `<type>.d`, then `<unit>.d` — so the type-wide OnFailure would be
# re-added on top of anything the unit file said, and only a *unit-specific*
# drop-in can clear it. Without that, a notifier that fails (no network, ntfy
# down — precisely when things are broken) retriggers itself forever.
{inputs, ...}: {
  den.aspects.core.notify-failure.nixos = {
    config,
    lib,
    pkgs,
    ...
  }: let
    inherit (lib.options) mkOption mkEnableOption;
    inherit (lib.types) int str;
    inherit (lib.modules) mkIf;

    cfg = config.cosmos.system.notifyFailure;

    notify = pkgs.writeShellApplication {
      name = "notify-failure";
      runtimeInputs = with pkgs; [curl systemd coreutils];
      text = ''
        unit="''${1:?usage: notify-failure <unit>}"

        # Wait, then ask again whether the unit is still down.
        #
        # systemd runs OnFailure= the moment a unit enters the failed state,
        # which is *before* its own Restart= brings it back. attic-watch-store
        # panics on an upstream bug and is healthy again 30 seconds later;
        # opencloud loses a subservice at boot and recovers on the next
        # restart. Both pushed a high-priority alert about a machine that was
        # fine by the time the phone buzzed, and an alert that is usually
        # wrong is one you learn to swipe away — including the night it is
        # right.
        #
        # The default covers the restart delays actually configured here
        # (RestartSec is 30s at the longest) with room to spare. A unit that is
        # still failed after that is failed in the sense worth waking up for.
        sleep ${toString cfg.settleSeconds}
        if ! systemctl is-failed --quiet "$unit"; then
          echo "$unit recovered on its own; not notifying"
          exit 0
        fi

        password="$(cat "$CREDENTIALS_DIRECTORY/ntfy-password")"

        # The last few lines are what makes the notification actionable rather
        # than just alarming. Trimmed hard: ntfy renders a message, not a log
        # viewer, and the full journal of a crash loop is unreadable on a phone.
        #
        # `|| true` is load-bearing. `systemctl status` exits 3 for a unit that
        # is dead or failed — which is every unit this will ever be called for
        # — and writeShellApplication runs under `set -euo pipefail`, so
        # without it the notifier aborts before sending and the alert is lost.
        # It passed a hand test only because the unit under test was running.
        body="$( { systemctl status --no-pager --lines=15 "$unit" || true; } 2>&1 | head -c 3000 )"

        # Retry, bounded. The failures worth reporting correlate with the
        # network being unwell, so the first POST is exactly when delivery is
        # least likely to work: two alerts were lost that way, one to a
        # two-minute uplink outage and one to DNS not being up yet after a
        # reboot. --retry-max-time caps the whole thing at five minutes so a
        # dead edge still cannot wedge the unit, and --retry-all-errors is
        # needed because curl otherwise treats a connect failure or a timeout
        # as not worth retrying.
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

      url = mkOption {
        type = str;
        default = "https://ntfy.lvdar.nl";
        description = ''
          The ntfy server. Public rather than the mesh address on purpose: the
          outages worth hearing about include "the mesh is down", and a sink
          only reachable over the mesh cannot report those.
        '';
      };

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

      topic = mkOption {
        type = str;
        default = "fleet";
        description = "ntfy topic every host publishes to.";
      };

      user = mkOption {
        type = str;
        default = "alerts";
        description = ''
          ntfy user to authenticate as. Its password is the shared secret
          `keys/ntfy/password`, and services/ntfy.nix provisions the account
          from the same value.
        '';
      };
    };

    config = mkIf cfg.enable {
      # From the common file: every host publishes as the same user, so this is
      # one secret encrypted to all four host keys rather than four copies to
      # keep in step.
      sops.secrets."keys/ntfy/password".sopsFile =
        builtins.toString inputs.nix-secrets + "/hosts/common/secrets.yaml";

      systemd.services."notify-failure@" = {
        description = "Report that %i failed";
        # Not wantedBy anything: it exists only to be triggered by OnFailure.
        serviceConfig = {
          Type = "oneshot";
          ExecStart = "${lib.getExe notify} %i";
          LoadCredential = "ntfy-password:${config.sops.secrets."keys/ntfy/password".path}";

          # systemd disables the start timeout entirely for Type=oneshot, so
          # this is a bound where there was none: without it a notifier wedged
          # on a half-open socket waits forever, holding a job slot, and the
          # unit shows as still "activating" long after the alert is moot.
          # Sized to fit what the script can legitimately take — the settle
          # wait plus the retry budget — with headroom.
          TimeoutStartSec = "10min";

          # It reaches the internet and reads one credential; nothing else.
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

      # Delivered as a systemd package rather than through environment.etc:
      # /etc/systemd/system is a symlink to a store-built units directory, so
      # nothing can be written inside it directly. generateUnits lndirs any
      # directory found under a package's lib/systemd/system, which is exactly
      # what a `.d` drop-in directory is.
      systemd.packages = [
        (pkgs.runCommand "notify-failure-dropins" {} ''
          d=$out/lib/systemd/system

          # Applies to every *.service on the host, present and future. %n is
          # the full unit name, which is what the notifier hands back to
          # `systemctl status`.
          mkdir -p $d/service.d
          cat > $d/service.d/50-notify-failure.conf <<'EOF'
          [Unit]
          OnFailure=notify-failure@%n.service
          EOF

          # The recursion guard, and the reason this is two files. The
          # type-wide drop-in above is applied *after* each unit file, so a
          # plain OnFailure= in the notifier's own unit would just be
          # overridden again. Only a unit-specific drop-in lands later still.
          # An empty assignment resets the list.
          # Verify: systemctl show notify-failure@x.service -p OnFailure
          mkdir -p "$d/notify-failure@.service.d"
          cat > "$d/notify-failure@.service.d/10-no-recursion.conf" <<'EOF'
          [Unit]
          OnFailure=
          EOF

          # The heredocs above are indented for readability; strip it.
          sed -i 's/^ *//' $d/service.d/*.conf "$d/notify-failure@.service.d"/*.conf
        '')
      ];
    };
  };
}
