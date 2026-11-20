# services.genix-boot — the GEHACK contest live system (genix) booted natively over the host's /nix, as a GRUB entry or a signed UKI.
{inputs, ...}: let
  # The self-hosted judge (services.domjudge.sso on endeavour). Trailing slash: submit
  # concatenates "api/..." to it verbatim.
  djUrl = "https://judge.lvdar.nl/";
in {
  flake-file.inputs.genix.url = "github:GEHACK/genix";

  den.aspects.services.genix-boot.nixos = {
    config,
    lib,
    pkgs,
    ...
  }: let
    inherit (lib.lists) filter;
    inherit (lib.strings) concatStringsSep hasPrefix removePrefix;

    user = config.cosmos.user.name;
    subvol = fs: removePrefix "subvol=" (lib.head (filter (hasPrefix "subvol=") fs.options));

    hostNix = config.fileSystems."/nix";

    upstream = inputs.genix.nixosConfigurations.teammachine-iso;
    # genix's team user trips HM's zsh dotDir warning, fatal under abort-on-warn.
    # Pinning the legacy default leaves the system unchanged.
    genix =
      lib.warnIf (lib.versionAtLeast upstream.config.home-manager.users.team.home.stateVersion "26.05")
      "services/genix-boot.nix: genix's team user is on HM stateVersion >= 26.05, so the zsh dotDir warning no longer fires; delete the dotDir pin"
      (upstream.extendModules {
        # dj_url is a specialArg, not an option: the NixOS value reaches only the greeter, and the
        # HM tools read it through home-manager.extraSpecialArgs, so override both.
        specialArgs.dj_url = djUrl;
        modules = [
          {home-manager.extraSpecialArgs.dj_url = djUrl;}
          {
            home-manager.users.team = {
              config,
              lib,
              ...
            }: {
              programs.zsh.dotDir = lib.mkDefault config.home.homeDirectory;

              # genix's users/team/gnome.nix sets this key too, and freeform dconf lists concatenate at
              # equal priority, so mkForce replaces rather than appends.
              dconf.settings."org/gnome/desktop/input-sources" = lib.mkForce {
                sources = [(lib.hm.gvariant.mkTuple ["xkb" "us+dvp"])];
                xkb-options = ["caps:escape"];
              };
            };
          }
          {
            # IDEs, VS Code and the ides editor set (nano/emacs/gedit/…) are
            # not wanted here; editing happens in genix's nixvim nvim.
            teammachine.users.team.ides.enable = lib.mkForce false;
            home-manager.users.team.programs.vscode.enable = lib.mkForce false;

            # Security: genix's sshd allows password login with the documented team password.
            services.openssh.enable = lib.mkForce false;

            # Practice toolset: C++ and Python only; drops the Java/Kotlin
            # JDKs, eclipse and netbeans.
            teammachine.users.team.languages = {
              c.enable = lib.mkForce false;
              cpp.enable = lib.mkForce true;
              python.enable = lib.mkForce true;
              java.enable = lib.mkForce false;
              kotlin.enable = lib.mkForce false;
            };

            # genix's DevDocs bookmark (docs.gehack.nl) only resolves on the
            # TU/e contest network; drop it, keep the judge.
            home-manager.users.team.programs.firefox.policies.Bookmarks = lib.mkForce [
              {
                Title = "DOMjudge";
                URL = djUrl;
                Placement = "toolbar";
              }
            ];

            # Security: the ISO's staff account has password "password" and passwordless sudo, i.e. root
            # over the host's unlocked disk. Locked; there is no root in genix.
            users.users.gehack = {
              hashedPassword = lib.mkForce "!";
              extraGroups = lib.mkForce [];
            };

            # genix denies NetworkManager actions to non-root users; let the team user join wifi.
            # polkit takes the first rule that answers, so this one goes first.
            security.polkit.extraConfig = lib.mkBefore ''
              polkit.addRule(function(action, subject) {
                if (action.id.indexOf("org.freedesktop.NetworkManager.") === 0 &&
                    subject.user === "team") {
                  return polkit.Result.YES;
                }
              });
            '';

            # The host's primary user is its first normal user, uid 1000, so
            # files in the shared subvolume belong to the same uid on both sides.
            users.users.team.uid = lib.mkForce 1000;

            # The host's layout (us dvp) from the first prompt on: LUKS passphrase, console and GDM.
            services.xserver.xkb = lib.mapAttrs (_: lib.mkForce) {
              inherit (config.services.xserver.xkb) layout variant options;
            };
            console = lib.mapAttrs (_: lib.mkForce) {
              useXkbConfig = true;
              earlySetup = true;
            };
          }
          {
            # genix's own kernel (6.18) predates the Framework 12's Wildcat
            # Lake (platform and Wi-Fi need >= 7.1); boot the host's.
            boot.kernelPackages = lib.mkForce config.boot.kernelPackages;
            boot.initrd.luks.devices =
              lib.mapAttrs (_: d: {inherit (d) device allowDiscards crypttabExtraOpts;})
              config.boot.initrd.luks.devices;
            boot.initrd.supportedFilesystems.btrfs = true;

            # The ISO's mounts, retargeted: /iso is the host's /nix
            # subvolume, and its store/ is the overlay's lower layer.
            fileSystems."/iso" = lib.mkForce {
              inherit (hostNix) device;
              fsType = "btrfs";
              options = ["subvol=${subvol hostNix}" "ro"];
              neededForBoot = true;
            };

            # Writable. nofail: the host creates it on its first boot with
            # this module (tmpfiles below).
            fileSystems."/home/team/shared" = {
              inherit (hostNix) device;
              fsType = "btrfs";
              options = ["subvol=${subvol config.fileSystems."/persist"}/genix" "compress=zstd" "noatime" "nofail"];
            };

            # Any write to a hibernated host's filesystem corrupts it on resume; systemd keeps the
            # hibernation image in this EFI variable until the host resumes.
            boot.initrd.systemd.services.genix-hibernation-guard = {
              description = "Refuse to boot while the host is hibernated";
              requiredBy = ["sysroot-iso.mount"];
              before = ["sysroot-iso.mount"];
              unitConfig.DefaultDependencies = false;
              serviceConfig.Type = "oneshot";
              script = ''
                if [ -e /sys/firmware/efi/efivars/HibernateLocation-8cf2644b-4b0b-428f-9387-6d876050dc67 ]; then
                  echo "genix: the host is hibernated; boot it, resume and shut down first" >/dev/console
                  exit 1
                fi
              '';
            };
            fileSystems."/nix/.ro-store" = lib.mkForce {
              # Not /sysroot/iso/store, unlike the squashfs it replaces: the
              # initrd's fstab generator prefixes bind sources with /sysroot.
              device = "/iso/store";
              fsType = "none";
              options = ["bind"];
              depends = ["/iso"];
              neededForBoot = true;
            };
          }
          ({
            config,
            lib,
            ...
          }: {
            # The host's store has no nix-path-registration, so the GRUB entry passes the closure's;
            # without it the store is empty to Nix and home-manager-team fails.
            systemd.services.register-nix-paths.script = lib.mkForce ''
              for o in $(</proc/cmdline); do
                case $o in genix.registration=*) registration=''${o#*=} ;; esac
              done
              ${lib.getExe' config.nix.package.out "nix-store"} --load-db <"$registration"
              touch /etc/NIXOS
              ${lib.getExe' config.nix.package.out "nix-env"} -p /nix/var/nix/profiles/system --set /run/current-system
            '';
          })
        ];
      }).config;
    registration = pkgs.closureInfo {rootPaths = [genix.system.build.toplevel];};

    kernel = "${genix.boot.kernelPackages.kernel}/${genix.system.boot.loader.kernelFile}";
    initrd = "${genix.system.build.initialRamdisk}/${genix.system.boot.loader.initrdFile}";
    cmdline = "init=${genix.system.build.toplevel}/init genix.registration=${registration}/registration ${concatStringsSep " " genix.boot.kernelParams}";
    title = "GEHACK contest workstation (genix)";

    secureBoot = config.boot.lanzaboote.enable;
    lanzaboote = config.boot.lanzaboote;
    esp = config.boot.loader.efi.efiSysMountPoint;
    osRelease = pkgs.writeText "genix-os-release" ''
      ID=genix
      PRETTY_NAME="${title}"
    '';
    # A UKI (kernel, initrd and command line in one EFI binary), so a single
    # signature covers all three. systemd-boot lists it from EFI/Linux.
    uki = pkgs.runCommand "genix.efi" {} ''
      ${pkgs.buildPackages.systemdUkify}/lib/systemd/ukify build \
        --linux=${kernel} \
        --initrd=${initrd} \
        --cmdline=${lib.escapeShellArg cmdline} \
        --os-release=@${osRelease} \
        --uname=${genix.boot.kernelPackages.kernel.modDirVersion} \
        --stub=${config.systemd.package}/lib/systemd/boot/efi/linuxx64.efi.stub \
        --output=$out
    '';
  in {
    config = lib.mkMerge [
      {
        # The live store is the host's: keep genix's closure in it.
        system.extraDependencies = [genix.system.build.toplevel registration];

        # The subvolume genix mounts as ~/shared ('v' creates a btrfs subvolume).
        systemd.tmpfiles.rules = [
          "v /persist/genix 0755 ${user} users -"
          "L+ /home/${user}/genix - - - - /persist/genix"
        ];

        # One-time boot into genix: GRUB's next_entry (grub-reboot), or systemd-boot's LoaderEntryOneShot.
        environment.systemPackages = [
          (pkgs.writeShellApplication {
            name = "genix";
            text = ''
              if [ "$(id -u)" -ne 0 ]; then
                exec sudo "$0" "$@"
              fi
              ${
                if secureBoot
                then "${lib.getExe' config.systemd.package "bootctl"} set-oneshot genix.efi"
                else "${lib.getExe' pkgs.grub2 "grub-editenv"} /boot/grub/grubenv set next_entry=genix"
              }
              systemctl reboot
            '';
          })
        ];
      }
      (lib.mkIf (!secureBoot) {
        boot.loader.grub = {
          extraFiles = {
            "genix/kernel" = kernel;
            "genix/initrd" = initrd;
          };
          extraEntries = ''
            menuentry "${title}" --id genix {
              linux @bootRoot@/genix/kernel ${cmdline}
              initrd @bootRoot@/genix/initrd
            }
          '';
        };
      })
      (lib.mkIf secureBoot {
        # lzbt signs only NixOS's own entries and GCs only nixos-* in EFI/Linux. Runs after
        # generate-sb-keys and before auto-enroll, whose autoReboot would cut it short.
        systemd.services.genix-uki = {
          description = "Sign genix's boot image onto the ESP";
          wantedBy = ["multi-user.target"];
          after = ["generate-sb-keys.service"];
          before = ["prepare-sb-auto-enroll.service"];
          unitConfig.RequiresMountsFor = [esp lanzaboote.pkiBundle];
          serviceConfig = {
            Type = "oneshot";
            RemainAfterExit = true;
          };
          script = ''
            mkdir -p ${esp}/EFI/Linux
            ${lib.getExe' pkgs.sbsigntool "sbsign"} --key ${lanzaboote.privateKeyFile} --cert ${lanzaboote.publicKeyFile} \
              --output ${esp}/EFI/Linux/genix.efi.tmp ${uki}
            mv ${esp}/EFI/Linux/genix.efi.tmp ${esp}/EFI/Linux/genix.efi
          '';
        };
      })
    ];
  };
}
