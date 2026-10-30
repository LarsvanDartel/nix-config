# voyager on the Framework Laptop 12 (Intel Core 3 304 / Wildcat Lake) — hardware profile; selected in hosts/voyager.nix.
{inputs}: {
  lib,
  pkgs,
  ...
}: {
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
}
