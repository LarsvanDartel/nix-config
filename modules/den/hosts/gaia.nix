# gaia (x86_64 server). den-produced; named `gaia` during the migration to
# avoid colliding with the old `gaia`.
#
# Hardware comes from a nixos-facter report (generate on the host — see below);
# filesystems from disko. This is the clean den hardware path: facter (unlike a
# nixos-generate-config hardware-configuration.nix) does not force
# nixpkgs.hostPlatform in a way that recurses, since den owns the host system.
#
# Generate the report on gaia and commit it:
#   sudo nixos-facter -o modules/den/hosts/_facter/gaia.facter.json
{
  den,
  inputs,
  ...
}: {
  den.hosts.x86_64-linux.gaia.users.nixos = {};

  den.aspects.gaia = {
    includes = with den.aspects; [
      roles.server
      core.boot
      core.impermanence
      services.pangolin
      services.typstnique
    ];

    nixos = {...}: {
      imports = [
        inputs.nixos-facter-modules.nixosModules.facter
        {facter.reportPath = ./_facter/gaia.facter.json;}
        inputs.disko.nixosModules.disko
        ../../hosts/gaia/_hw/disko.nix
      ];

      cosmos.system = {
        boot = {
          legacy = true;
          grub-device = "/dev/sda";
        };
        impermanence.device = "/dev/disk/by-label/nixos";
      };

      system.stateVersion = "24.11";
    };
  };
}
