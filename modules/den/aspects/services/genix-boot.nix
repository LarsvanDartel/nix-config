# services.genix-boot — the GEHACK contest workstation (genix) as a GRUB entry.
#
# genix's live system, booted natively: its kernel and initrd sit on the ESP,
# its stage 1 unlocks the host's LUKS (FIDO2 or passphrase) and uses the
# host's /nix subvolume, read-only, as the lower layer of its tmpfs store
# overlay. No ISO and no squashfs, so nothing to fit on the ESP; still a live
# system, so every boot is a fresh machine, like a contest morning. Nothing of
# the host but /nix is mounted.
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
    inherit (lib.lists) filter take;
    inherit (lib.strings) concatStringsSep hasPrefix;

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

            # genix ships GEHACK's keys for the team user, which would open
            # this laptop to them on any network it boots on.
            users.users.team.openssh.authorizedKeys.keys = lib.mkForce [
              "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAINXY0u3IG0XLICWx3ZWGqfiKLoDSnl1IDqkhHYeFd8sD lars@lvdar.nl"
            ];

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

            # The ISO ships GEHACK's staff account: wheel, passwordless sudo
            # and the org's SSH keys. Dead weight on a private practice boot.
            users.users.gehack = {
              hashedPassword = lib.mkForce "!";
              extraGroups = lib.mkForce [];
              openssh.authorizedKeys.keyFiles = lib.mkForce [];
            };
          }
          {
            boot.initrd.luks.devices =
              lib.mapAttrs (_: d: {inherit (d) device allowDiscards crypttabExtraOpts;})
              config.boot.initrd.luks.devices;
            boot.initrd.supportedFilesystems.btrfs = true;

            # The ISO's mounts, retargeted: /iso is the host's /nix
            # subvolume, and its store/ is the overlay's lower layer.
            fileSystems."/iso" = lib.mkForce {
              inherit (hostNix) device;
              fsType = "btrfs";
              # Even a read-only btrfs mount replays a pending log tree,
              # i.e. writes, e.g. into a hibernated host's filesystem.
              options = take 1 (filter (hasPrefix "subvol=") hostNix.options) ++ ["ro" "rescue=nologreplay"];
              neededForBoot = true;
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
  in {
    # The live store is the host's: keep genix's closure in it.
    system.extraDependencies = [genix.system.build.toplevel registration];

    boot.loader.grub = {
      extraFiles = {
        "genix/kernel" = "${genix.boot.kernelPackages.kernel}/${genix.system.boot.loader.kernelFile}";
        "genix/initrd" = "${genix.system.build.initialRamdisk}/${genix.system.boot.loader.initrdFile}";
      };
      extraEntries = ''
        menuentry "GEHACK contest workstation (genix)" {
          linux @bootRoot@/genix/kernel init=${genix.system.build.toplevel}/init genix.registration=${registration}/registration ${concatStringsSep " " genix.boot.kernelParams}
          initrd @bootRoot@/genix/initrd
        }
      '';
    };
  };
}
