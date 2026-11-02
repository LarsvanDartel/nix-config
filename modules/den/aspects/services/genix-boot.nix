# services.genix-boot — the GEHACK contest workstation (genix) as a boot entry (GRUB, or a signed UKI under lanzaboote).
#
# genix's live system, booted natively: its kernel and initrd sit on the ESP,
# its stage 1 unlocks the host's LUKS (FIDO2 or passphrase) and uses the
# host's /nix subvolume, read-only, as the lower layer of its tmpfs store
# overlay. No ISO and no squashfs, so nothing to fit on the ESP; still a live
# system, so every boot is a fresh machine, like a contest morning. Of the
# host it mounts only /nix and the /persist/genix subvolume, which is
# ~/shared in genix and ~/genix on the host.
{inputs, ...}: let
  # The self-hosted judge (services.domjudge.sso on endeavour). Trailing
  # slash: submit concatenates it with "api/..." verbatim. Upstream points
  # the live system at the public DOMjudge demo instead.
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
        # dj_url is a specialArg of genix's flake, not an option; extendModules
        # merges specialArgs, ours winning. The NixOS-level value only reaches
        # the greeter module; the HM tools (submit, Firefox) read the same
        # specialArg through home-manager.extraSpecialArgs, so override both.
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

              # The user's contest layout, baked in: the live system starts
              # fresh every time, so the TRD's gsettings step would be
              # per-session. genix's own users/team/gnome.nix already sets
              # this key (us+nl); dconf.settings is freeform and merges same-
              # priority list values by concatenation, so mkForce is required
              # to replace rather than append.
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

            # genix runs sshd with password login, and the team password is
            # the documented "password": with wifi, anyone on the network
            # could log in and read ~/shared.
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

            # The ISO ships GEHACK's staff account: password "password", wheel
            # and passwordless sudo, i.e. root over the host's unlocked disk
            # from the login screen. Locked; there is no root in genix.
            users.users.gehack = {
              hashedPassword = lib.mkForce "!";
              extraGroups = lib.mkForce [];
            };

            # genix denies every NetworkManager action to non-root users
            # (contest machines are wired); allow the team user to join wifi.
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

            # A hibernated host resumes onto the filesystem as it left it, so
            # any write from here (the shared subvolume, or the log replay a
            # mount does) corrupts it. systemd records the hibernation image in
            # this EFI variable until the host resumes.
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
            # The ISO registers its paths from the squashfs's
            # nix-path-registration; the host's store has none, so the
            # GRUB entry passes the closure's registration instead. Without
            # it the store is empty to Nix and home-manager-team fails.
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

        # One-time boot into genix. GRUB: install-grub's grub.cfg boots
        # next_entry once (the grub-reboot mechanism). systemd-boot: the
        # LoaderEntryOneShot EFI variable.
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
        # lzbt signs only NixOS's own entries, and garbage-collects only the
        # nixos-* files in EFI/Linux. Runs on every boot and on each switch
        # that changes the image; after generate-sb-keys, and before the
        # auto-enroll unit, whose autoReboot would cut this short.
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
