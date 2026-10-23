# hardware.ipmi-fancontrol — dynamic IPMI fan control (server chassis).
{...}: {
  den.aspects.hardware.ipmi-fancontrol.nixos = {
    config,
    lib,
    pkgs,
    ...
  }: let
    inherit (lib.options) mkEnableOption mkOption;
    inherit (lib.types) bool int float listOf str;
    inherit (lib.modules) mkIf;
    inherit (lib.strings) optionalString concatMapStringsSep hasInfix;

    cfg = config.cosmos.hardware.ipmi-fancontrol;
    pollInterval = toString cfg.pollInterval;
    minSpeed = toString cfg.minSpeed;
    manualSpeed = toString cfg.manualSpeed;
    curve = toString cfg.curve;
    gpuMaxTemp = toString cfg.nvidia-smi.maxTemp;
    nvidia_x11 = config.hardware.nvidia.package;

    # nixpkgs#576412: patchelf 0.19.2 setting interpreter and rpath in one call
    # yields overlapping LOAD segments, and the driver's nvidia-smi segfaults
    # in ld.so. This loop set the fans to manual first, then died: fans stuck.
    # Re-patch the pristine origBin copy in two calls, rpath first (the fix in
    # nixpkgs#576397); warns once the locked builder.sh drops the combined call.
    nvidiaBuilder = pkgs.path + "/pkgs/os-specific/linux/nvidia-x11/builder.sh";
    nvidiaSmi =
      lib.warnIfNot (builtins.pathExists nvidiaBuilder && hasInfix "--set-rpath $out/lib:$libPath $bin/bin/$i" (builtins.readFile nvidiaBuilder)) ''
        modules/den/aspects/hardware/ipmi-fancontrol.nix: nixpkgs' nvidia builder no longer sets interpreter and rpath in one patchelf call (nixpkgs#576397).
        Drop nvidiaSmi and use the driver's own nvidia-smi.
      ''
      (pkgs.runCommand "nvidia-smi-repatched" {nativeBuildInputs = [pkgs.patchelf];} ''
        install -Dm755 ${nvidia_x11.bin}/origBin/nvidia-smi $out/bin/nvidia-smi
        patchelf --set-rpath "$(patchelf --print-rpath ${nvidia_x11.bin}/bin/nvidia-smi)" $out/bin/nvidia-smi
        patchelf --interpreter "$(patchelf --print-interpreter ${nvidia_x11.bin}/bin/nvidia-smi)" $out/bin/nvidia-smi
      '');
  in {
    options.cosmos.hardware.ipmi-fancontrol = {
      dynamic = mkOption {
        type = bool;
        default = false;
      };
      pollInterval = mkOption {
        type = int;
        default = 10;
      };
      minSpeed = mkOption {
        type = int;
        default = 30;
      };
      manualSpeed = mkOption {
        type = int;
        default = 60;
      };
      ignoreDevices = mkOption {
        type = listOf str;
        default = [];
      };
      curve = mkOption {
        type = float;
        default = 2.5;
      };
      nvidia-smi = {
        enable = mkEnableOption "reading GPU temperature via nvidia-smi";
        maxTemp = mkOption {
          type = int;
          default = 105;
        };
      };
    };

    config.systemd.services.ipmi-fan-control = {
      description = "IPMI Fan Control";
      wantedBy = ["multi-user.target"];
      after = ["network.target"];
      serviceConfig = {
        Type =
          if cfg.dynamic
          then "simple"
          else "oneshot";
        RemainAfterExit = mkIf (!cfg.dynamic) true;
        Restart = mkIf cfg.dynamic "always";
        ExecStart = let
          script = pkgs.writeShellScript "ipmi-fan-control.sh" ''
            set -euo pipefail
            ${pkgs.ipmitool}/bin/ipmitool raw 0x30 0x30 0x01 0x00

            ${optionalString cfg.dynamic ''
              while true; do
                mapfile -t lines < <(
                  ${pkgs.lm_sensors}/bin/sensors \
                  | grep -E "([0-9]+\.[0-9]+)°C" \
                  | grep -E "high =" \
                  ${optionalString
                (cfg.ignoreDevices != [])
                (concatMapStringsSep "\\\n" (d: ''| grep -v "${d}"'') cfg.ignoreDevices)}
                )

                max_ratio=0
                for line in "''${lines[@]}"; do
                  current=$(echo "$line" | grep -Eo "\+[0-9]+\.[0-9]+" | head -n1 | tr -d "+")
                  high=$(echo "$line" | grep -Eo "high = \+[0-9]+\.[0-9]+" | grep -Eo "[0-9]+\.[0-9]+" | head -n1)

                  if [ -z "$current" ] || [ -z "$high" ]; then
                    continue
                  fi

                  threshold=$(${pkgs.gawk}/bin/awk "BEGIN {print 0.8 * $high}")
                  ratio=$(${pkgs.gawk}/bin/awk "BEGIN {print $current / $threshold}")
                  [ "$(${pkgs.gawk}/bin/awk "BEGIN {print ($ratio > 1)}")" -eq 1 ] && ratio=1

                  [ "$(${pkgs.gawk}/bin/awk "BEGIN {print ($ratio > $max_ratio)}")" -eq 1 ] && max_ratio=$ratio
                done

                ${optionalString cfg.nvidia-smi.enable ''
                gpu_temp=$(${nvidiaSmi}/bin/nvidia-smi --query-gpu=temperature.gpu --format=csv,noheader,nounits | head -n1)
                gpu_ratio=$(${pkgs.gawk}/bin/awk "BEGIN {print $gpu_temp / ${gpuMaxTemp}}")
                [ "$(${pkgs.gawk}/bin/awk "BEGIN {print ($gpu_ratio > 1)}")" -eq 1 ] && gpu_ratio=1
                [ "$(${pkgs.gawk}/bin/awk "BEGIN {print ($gpu_ratio > $max_ratio)}")" -eq 1 ] && max_ratio=$gpu_ratio
              ''}

                speed=$(${pkgs.gawk}/bin/awk "BEGIN {print int(${minSpeed} + (100 - ${minSpeed}) * ($max_ratio ^ ${curve}))}")
                [ "$speed" -gt 100 ] && speed=100
                printf "max ratio: %.2f, setting fan speed to %s%%\n" "$max_ratio" "$speed"
                ${pkgs.ipmitool}/bin/ipmitool raw 0x30 0x30 0x02 0xff $(printf "0x%02x" $speed)
                sleep ${pollInterval}
              done
            ''}
            ${optionalString (!cfg.dynamic) ''
              ${pkgs.ipmitool}/bin/ipmitool raw 0x30 0x30 0x02 0xff $(printf "0x%02x" ${manualSpeed})
            ''}
          '';
        in "${script}";

        ExecStop = ''
          ${pkgs.ipmitool}/bin/ipmitool raw 0x30 0x30 0x01 0x01
        '';
      };
    };
  };
}
