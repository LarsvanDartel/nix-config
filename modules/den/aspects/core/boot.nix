# core.boot — grub bootloader (or lanzaboote with Secure Boot) + the cosmos.system.boot options. Opt-in per host.
{inputs, ...}: {
  flake-file.inputs.lanzaboote = {
    url = "github:nix-community/lanzaboote/v1.2.0";
    inputs = {
      nixpkgs.follows = "nixpkgs";
      pre-commit.follows = "pre-commit-hooks";
    };
  };

  den.aspects.core.boot.nixos = {
    config,
    lib,
    pkgs,
    ...
  }: let
    inherit (lib.options) mkOption;
    inherit (lib.types) bool int nullOr str;

    cfg = config.cosmos.system.boot;
  in {
    imports = [inputs.lanzaboote.nixosModules.lanzaboote];

    options.cosmos.system.boot = {
      configurationLimit = mkOption {
        type = int;
        default = 10;
        description = ''
          Generations kept in the boot menu. GRUB's own default is 100, which
          no EFI system partition can hold: each distinct kernel build costs
          its bzImage plus its initrd, and once the ESP fills, installing the
          bootloader fails *after* the system has already been built.

          Sized for a 512 MiB ESP at roughly 65 MiB per distinct kernel build.
          Generations sharing a nixpkgs revision share those files, so ten
          menu entries are normally two or three kernels' worth.
        '';
      };

      secureBoot = mkOption {
        type = bool;
        default = false;
        description = ''
          Secure Boot: lanzaboote (systemd-boot with signed images) instead of
          GRUB. The keys are generated in /var/lib/sbctl on the first boot and
          enrolled by systemd-boot once the firmware is in setup mode; see
          docs/src/install.md, "Secure Boot".
        '';
      };

      legacy = mkOption {
        type = bool;
        default = false;
        description = "Whether to use legacy BIOS";
      };
      grub-device = mkOption {
        type = nullOr str;
        default = null;
        description = "Device to install grub on";
      };
      detect-windows = mkOption {
        type = bool;
        default = false;
        description = "Whether to check for windows partitions";
      };
    };

    config = lib.mkMerge [
      {
        assertions = [
          {
            assertion = !cfg.legacy || cfg.grub-device != null;
            message = "boot: grub device must be defined when using legacy BIOS";
          }
          {
            assertion = !(cfg.legacy && cfg.secureBoot);
            message = "boot: Secure Boot needs UEFI";
          }
        ];
        boot.loader = {
          efi.canTouchEfiVariables = !cfg.legacy;
          grub = {
            enable = !cfg.secureBoot;
            device =
              if cfg.grub-device == null
              then "nodev"
              else cfg.grub-device;
            efiSupport = !cfg.legacy;
            useOSProber = cfg.detect-windows;
            inherit (cfg) configurationLimit;
          };
        };
      }
      (lib.mkIf cfg.secureBoot {
        boot.lanzaboote = {
          enable = true;
          pkiBundle = "/var/lib/sbctl";
          inherit (cfg) configurationLimit;
          autoGenerateKeys.enable = true;
          # Not autoReboot: its reboot would land in the middle of the switch
          # that first enables this.
          autoEnrollKeys.enable = true;
        };
        # No kernel command-line edits (init=/bin/sh) from the boot menu, not
        # even before the keys are enrolled.
        boot.loader.systemd-boot.editor = false;

        cosmos.system.impermanence.persist.directories = [
          {
            directory = "/var/lib/sbctl";
            mode = "0700";
          }
        ];
        # On the switch that enables this, the persist bind mount appears
        # during activation: keys written before it would be hidden by it and
        # lost, while the ESP already holds their enrolment files.
        systemd.services.generate-sb-keys.unitConfig.RequiresMountsFor = ["/var/lib/sbctl"];
        systemd.services.prepare-sb-auto-enroll.unitConfig.RequiresMountsFor = ["/var/lib/sbctl"];

        # lzbt never creates a firmware boot entry; efibootmgr does.
        environment.systemPackages = [pkgs.sbctl pkgs.efibootmgr];
      })
    ];
  };
}
