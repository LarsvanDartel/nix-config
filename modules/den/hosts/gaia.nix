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
      # Pangolin stays up alongside NetBird until the mesh is proven; gaia is
      # the only public entry point, so there is no second way back in.
      services.pangolin
      services.netbird
      services.typstnique
    ];

    nixos = {...}: {
      imports = [
        inputs.nixos-facter-modules.nixosModules.facter
        {
          facter.reportPath = ./_facter/gaia.facter.json;
          # Headless VM: skip graphics detection (mesa/llvm ~800MB). Set alongside
          # reportPath so it isn't a config-read that recurses under den.
          facter.detected.graphics.enable = false;
        }
        inputs.disko.nixosModules.disko
        ./_hw/gaia/disko.nix
      ];

      cosmos.system = {
        boot = {
          legacy = true;
          grub-device = "/dev/sda";
        };
        impermanence.device = "/dev/disk/by-label/nixos";
      };

      # The published surface. Targets are peer name + port: den has no way to
      # read another host's config, so the ports are literals here and must
      # track the aspects that own them (jellyfin.nix, traccar.nix, …).
      #
      # INCOMPLETE until the Pangolin resource list is enumerated — `cloud`
      # (opencloud) is published today but is not deployed from this repo at
      # all, so there is nothing here to point at.
      cosmos.services.netbird.services = {
        # Not gated: NetBird's own dashboard authenticates against kanidm, so
        # putting a NetBird identity check in front of kanidm would lock
        # everyone out of the thing that grants the identity.
        auth = {
          bearerAuth.enable = false;
          targets = [
            {
              peer = "endeavour";
              port = 8443;
              protocol = "https";
            }
          ];
        };

        jellyfin.targets = [
          {
            peer = "endeavour";
            port = 8096;
          }
        ];

        immich.targets = [
          {
            peer = "endeavour";
            port = 2283;
          }
        ];

        traccar.targets = [
          {
            peer = "endeavour";
            port = 8082;
          }
        ];

        # VPN-confined: these run inside endeavour's netns, so they are reached
        # through the nginx bridges in arr/default.nix rather than directly.
        seerr.targets = [
          {
            peer = "endeavour";
            port = 4055;
          }
        ];

        sabnzbd.targets = [
          {
            peer = "endeavour";
            port = 6336;
          }
        ];

        suwayomi.targets = [
          {
            peer = "endeavour";
            port = 8080;
          }
        ];
      };

      system.stateVersion = "24.11";
    };
  };
}
