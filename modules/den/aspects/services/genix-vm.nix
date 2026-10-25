# services.genix-vm — the GEHACK contest workstation (genix live ISO) as an on-demand VM.
#
# Contest practice: `sudo systemctl start genix-vm`, then SPICE (Remmina) to
# 127.0.0.1:5930 through an SSH tunnel to this host. Loopback only: SPICE has
# no auth here and the guest autologins. Live ISO, so every start is a fresh
# machine, like a contest morning.
{inputs, ...}: let
  spicePort = 5930;
in {
  flake-file.inputs.genix.url = "github:GEHACK/genix";

  den.aspects.services.genix-vm.nixos = {
    lib,
    pkgs,
    ...
  }: let
    upstream = inputs.genix.nixosConfigurations.teammachine-iso;
    # genix's team user trips HM's zsh dotDir warning, fatal under abort-on-warn.
    # Pinning the legacy default leaves the ISO's derivation unchanged.
    genix =
      lib.warnIf (lib.versionAtLeast upstream.config.home-manager.users.team.home.stateVersion "26.05")
      "services/genix-vm.nix: genix's team user is on HM stateVersion >= 26.05, so the zsh dotDir warning no longer fires; delete the dotDir pin"
      (upstream.extendModules {
        modules = [
          {
            home-manager.users.team = {config, ...}: {
              programs.zsh.dotDir = lib.mkDefault config.home.homeDirectory;
            };
          }
        ];
      }).config;
  in {
    systemd.services.genix-vm = {
      description = "GEHACK contest workstation VM";
      serviceConfig = {
        DynamicUser = true;
        SupplementaryGroups = ["kvm"];
      };
      # Globbed: genix's image.fileName (gehack-teammachine.iso) does not reach
      # the builder, which writes nixos-<version>-x86_64-linux.iso instead.
      script = ''
        exec ${pkgs.qemu_kvm}/bin/qemu-system-x86_64 \
          -name genix -machine q35,accel=kvm -cpu host -smp 4 -m 8G \
          -drive file="$(echo ${genix.system.build.isoImage}/iso/*.iso)",media=cdrom,readonly=on \
          -vga none -device virtio-vga,xres=1920,yres=1080 \
          -device qemu-xhci -device usb-tablet \
          -nic user,model=virtio-net-pci \
          -display none -spice addr=127.0.0.1,port=${toString spicePort},disable-ticketing=on
      '';
    };
  };
}
