# voyager on the Framework Laptop 12 (Intel Core 3 304 / Wildcat Lake) — hardware module; imported by hosts/voyager.nix.
{inputs}: {
  config,
  lib,
  pkgs,
  ...
}: let
  # Re-probing the PixArt touchpad through i2c_hid_acpi clears both of its
  # failure modes (below).
  touchpadRebind = pkgs.writeShellScript "touchpad-rebind" ''
    dev=i2c-PIXA3854:00
    drv=/sys/bus/i2c/drivers/i2c_hid_acpi
    [ -e /sys/bus/i2c/devices/$dev ] || exit 0
    if [ -e $drv/$dev ]; then echo $dev > $drv/unbind; fi
    echo $dev > $drv/bind
  '';
in {
  # Not framework-12-13th-gen-intel: it loads pinctrl_tigerlake. common/ brings laptop+ssd profiles, the Framework kmod, framework-tool, iio and fwupd.
  imports = ["${inputs.nixos-hardware}/framework/12-inch/common"];

  # Wildcat Lake (platform + BE213 Wi-Fi) needs >= 7.1.
  boot.kernelPackages =
    lib.warnIf (lib.versionAtLeast pkgs.linuxPackages.kernel.version "7.1")
    "hosts/_hw/voyager/framework-12.nix: nixpkgs' default kernel is now >= 7.1; delete the linuxPackages_latest override"
    pkgs.linuxPackages_latest;

  # Tablet-mode switch: soc_button_array needs the pin controller first (FrameworkComputer/linux-docs framework12/nixOS.md).
  boot.initrd.kernelModules =
    lib.warnIf (builtins.pathExists "${inputs.nixos-hardware}/framework/12-inch/intel-core-series3")
    "hosts/_hw/voyager/framework-12.nix: nixos-hardware now ships framework/12-inch/intel-core-series3; import nixosModules.framework-12-intel-core-series3 instead of 12-inch/common and delete this pinctrl block and its softdep"
    ["pinctrl_intel_platform"];
  boot.extraModprobeConfig = ''
    softdep soc_button_array pre: pinctrl_intel_platform
  '';

  # VA-API for the Xe3 iGPU: Mesa has no Intel video driver, so without iHD
  # browsers and mpv decode on the CPU (GeForce NOW stutters).
  hardware.graphics.extraPackages = [pkgs.intel-media-driver];

  # The PixArt touchpad (PIXA3854) fails two ways, neither leaving a cursor:
  # - after hibernation it can come back silent, no interrupts at all;
  # - on some boots and resumes it never enters precision-touchpad mode and
  #   reports through its legacy Mouse collection, whose unsigned relative
  #   motion only runs down/right, so the cursor lands off-screen. In touchpad
  #   mode that collection sends nothing, so any motion from it means this mode.
  systemd.services =
    lib.warnIf (lib.versions.majorMinor config.boot.kernelPackages.kernel.version != "7.3")
    "hosts/_hw/voyager/framework-12.nix: the kernel is no longer 7.3; mask touchpad-resume-rebind and touchpad-mode-watch, then hibernate and cold-boot voyager several times; if the touchpad always moves the cursor delete both units, else bump this guard"
    {
      touchpad-resume-rebind = {
        description = "Re-probe the touchpad after resuming from hibernation";
        wantedBy = ["hibernate.target" "hybrid-sleep.target" "suspend-then-hibernate.target"];
        after = ["systemd-hibernate.service" "systemd-hybrid-sleep.service" "systemd-suspend-then-hibernate.service"];
        serviceConfig.Type = "oneshot";
        script = "${touchpadRebind}";
      };

      touchpad-mode-watch = {
        description = "Re-probe the touchpad when it falls back to its legacy mouse mode";
        wantedBy = ["multi-user.target"];
        serviceConfig.Restart = "always";
        script = ''
          while :; do
            mouse=
            for d in /sys/class/input/event*; do
              if [ "$(cat "$d/device/name")" = "PIXA3854:00 093A:0239 Mouse" ]; then mouse=/dev/input/''${d##*/}; fi
            done
            if [ -n "$mouse" ]; then
              while read -r line; do
                case "$line" in *POINTER_MOTION*) ${touchpadRebind}; break ;; esac
              done < <(exec ${lib.getExe' pkgs.libinput "libinput"} debug-events --device "$mouse")
              kill $! 2>/dev/null || true
            fi
            # Also paces re-probes should one land in the legacy mode again.
            sleep 5
          done
        '';
      };
    };

  # fwupd (from nixos-hardware) records a staged capsule update here and
  # checks its result after the update reboot; the root rollback would drop it.
  cosmos.system.impermanence.persist.directories = ["/var/lib/fwupd"];

  # Under cosmos.system.boot.secureBoot: Framework's own EFI tools (the BIOS
  # updater) are signed with its db/KEK, which erasing the keys removes.
  boot.lanzaboote.autoEnrollKeys.includeFirmwareBuiltinKeys = true;
}
