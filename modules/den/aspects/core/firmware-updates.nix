# core.firmware-updates — push a notification when fwupd has a firmware update for this host. Inert without services.fwupd.
{inputs, ...}: {
  den.aspects.core.firmware-updates.nixos = {
    config,
    lib,
    pkgs,
    ...
  }: let
    inherit (lib.options) mkEnableOption;
    inherit (lib.modules) mkIf;

    cfg = config.cosmos.system.firmwareUpdates;
    notifyCfg = config.cosmos.system.notifyFailure;
    stateDir = "/var/lib/firmware-updates";

    check = pkgs.writeShellApplication {
      name = "firmware-updates-check";
      runtimeInputs = [config.services.fwupd.package] ++ (with pkgs; [curl coreutils jq]);
      text = ''
        # --json never prompts and exits 0; a device without an update is
        # left out, and Releases lists the newest first.
        current="$(mktemp)"
        fwupdmgr get-updates --json |
          jq -r '.Devices[] | select((.Releases // []) | length > 0)
            | [.DeviceId, .Name, (.Version // "?"), .Releases[0].Version] | @tsv' |
          sort >"$current"

        # fwupd-refresh runs hourly; say each new version once. An installed
        # update drops out of the list, and so out of the record.
        seen="${stateDir}/notified"
        touch "$seen"
        new="$(comm -13 "$seen" "$current")"
        if [ -z "$new" ]; then
          cp "$current" "$seen"
          echo "no new firmware updates"
          exit 0
        fi

        body=""
        while IFS=$'\t' read -r _ name installed available; do
          body+="$name: $installed -> $available"$'\n'
        done <<<"$new"
        echo "$body"
        password="$(cat "$CREDENTIALS_DIRECTORY/ntfy-password")"

        # Recorded only once sent: a failed push is retried on the next refresh.
        curl -sS --fail --max-time 20 \
          -u "${notifyCfg.user}:$password" \
          -H "Title: ${config.networking.hostName}: firmware update available" \
          -H "Priority: default" \
          -H "Tags: package" \
          -d "$body
        Plug in the charger, then run fwupdmgr update (docs/src/install.md, Firmware updates)." \
          "${notifyCfg.url}/${notifyCfg.topic}"
        cp "$current" "$seen"
      '';
    };
  in {
    options.cosmos.system.firmwareUpdates.enable =
      mkEnableOption "a push notification when fwupd offers a firmware update"
      // {default = true;};

    config = mkIf (cfg.enable && config.services.fwupd.enable) {
      # Also declared by core.notify-failure; keeps this working without it.
      sops.secrets."keys/ntfy/password".sopsFile =
        builtins.toString inputs.nix-secrets + "/hosts/common/secrets.yaml";

      cosmos.system.impermanence.persist.directories = [
        {
          directory = stateDir;
          user = "fwupd-refresh";
          group = "fwupd-refresh";
        }
      ];

      # After every successful metadata refresh (hourly, upstream's timer).
      systemd.services.fwupd-refresh.onSuccess = ["firmware-updates.service"];

      systemd.services.firmware-updates = {
        description = "Report available firmware updates";
        serviceConfig = {
          Type = "oneshot";
          ExecStart = lib.getExe check;
          LoadCredential = "ntfy-password:${config.sops.secrets."keys/ntfy/password".path}";

          # fwupd-refresh's static user (services.fwupd): not DynamicUser,
          # whose persisted /var/lib/private state is the EBUSY trap.
          User = "fwupd-refresh";
          Group = "fwupd-refresh";
          StateDirectory = "firmware-updates";

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
    };
  };
}
