{
  config,
  lib,
  pkgs,
  ...
}: let
  inherit (lib.options) mkEnableOption mkOption;
  inherit (lib.types) bool int float;
  inherit (lib.modules) mkIf;

  cfg = config.hardware.ipmi-fancontrol;
  pollInterval = toString cfg.pollInterval;
  minSpeed = toString cfg.minSpeed;
  manualSpeed = toString cfg.manualSpeed;
  curve = toString cfg.curve;
in {
  options.hardware.ipmi-fancontrol = {
    enable = mkEnableOption "Enable fan control via ipmitool";

    dynamic = mkOption {
      type = bool;
      default = false;
      description = "Dynamically adjust fan speed based on all temperature sensors.";
    };

    pollInterval = mkOption {
      type = int;
      default = 10;
      description = "Seconds between temperature checks.";
    };

    minSpeed = mkOption {
      type = int;
      default = 30;
      description = "Minimum fan speed percentage at cool temps.";
    };

    manualSpeed = mkOption {
      type = int;
      default = 60;
      description = "Fixed fan speed percentage for manual mode.";
    };

    curve = mkOption {
      type = float;
      default = 2.5;
      description = ''
        Exponential curve exponent for mapping ratio to fan speed.
        - curve < 1: more aggressive early (higher fan at low temps).
        - curve = 1: linear.
        - curve > 1: slower ramp early, aggressive later.
      '';
    };
  };

  config = mkIf cfg.enable {
    systemd.services.ipmi-fan-control = {
      description = "IPMI Fan Control";
      wantedBy = ["multi-user.target"];
      after = ["network.target"];
      serviceConfig = {
        Type = "simple";
        ExecStart =
          if cfg.dynamic
          then ''
            ${pkgs.bash}/bin/bash -euo pipefail -c '
              ${pkgs.ipmitool}/bin/ipmitool raw 0x30 0x30 0x01 0x00
              while true; do
                mapfile -t lines < <(${pkgs.lm_sensors}/bin/sensors | grep -E "([0-9]+\.[0-9]+)°C" | grep -E "high =")

                max_ratio=0
                for line in "''${lines[@]}"; do
                  current=$(echo "$line" | grep -Eo "\+[0-9]+\.[0-9]+" | head -n1 | tr -d "+")
                  high=$(echo "$line" | grep -Eo "high = \+[0-9]+\.[0-9]+" | grep -Eo "[0-9]+\.[0-9]+" | head -n1)

                  if [ -z "$current" ] || [ -z "$high" ]; then
                    continue
                  fi

                  threshold=$(awk "BEGIN {print 0.8 * $high}")
                  ratio=$(awk "BEGIN {print $current / $threshold}")
                  [ "$(awk "BEGIN {print ($ratio > 1)}")" -eq 1 ] && ratio=1

                  [ "$(awk "BEGIN {print ($ratio > $max_ratio)}")" -eq 1 ] && max_ratio=$ratio
                done

                speed=$(awk "BEGIN {print int(${minSpeed} + (100 - ${minSpeed}) * $max_ratio ^ ${curve})}")
                [ "$speed" -gt 100 ] && speed=100
                pwm=$(( speed * 255 / 100 ))

                printf "max ratio: %.2f, setting fan speed to %s%%\n" "$max_ratio" "$speed"
                ${pkgs.ipmitool}/bin/ipmitool raw 0x30 0x30 0x02 0xff $(printf "0x%02x" $pwm)
                sleep ${pollInterval}
              done
            '
          ''
          else ''
            ${pkgs.ipmitool}/bin/ipmitool raw 0x30 0x30 0x01 0x00
            ${pkgs.ipmitool}/bin/ipmitool raw 0x30 0x30 0x02 0xff $(printf "0x%02x" $(( ${manualSpeed} * 255 / 100 )))
          '';
        ExecStop = ''
          ${pkgs.ipmitool}/bin/ipmitool raw 0x30 0x30 0x01 0x01
        '';
        Restart = "always";
      };
    };
  };
}
