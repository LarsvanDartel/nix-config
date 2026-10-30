# services.genix-vm — the GEHACK contest workstation (genix live ISO) as an on-demand VM.
#
# Contest practice: `sudo systemctl start genix-vm`, then SPICE (Remmina) to
# 127.0.0.1:5930. Loopback only: SPICE has no auth here and the guest
# autologins. Live ISO, so every start is a fresh machine, like a contest
# morning.
{inputs, ...}: let
  spicePort = 5930;
  # The self-hosted judge (services.domjudge.sso on endeavour), reachable
  # from the guest over its slirp NAT. Trailing slash: submit concatenates
  # it with "api/..." verbatim. Upstream points the live ISO at the public
  # DOMjudge demo instead.
  djUrl = "https://judge.lvdar.nl/";
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

              # The user's contest layout, baked in: the live ISO starts
              # fresh every time, so the TRD's gsettings step would be
              # per-session.
              dconf.settings."org/gnome/desktop/input-sources" = {
                sources = [(lib.hm.gvariant.mkTuple ["xkb" "us+dvorak"])];
                xkb-options = ["caps:escape"];
              };
            };
          }
          {
            # IDEs, VS Code and the ides editor set (nano/emacs/gedit/…) are
            # not wanted here; editing happens in genix's nixvim nvim.
            teammachine.users.team.ides.enable = lib.mkForce false;
            home-manager.users.team.programs.vscode.enable = lib.mkForce false;

            # SSH in from the host over the slirp forward to drop the TRD
            # toolchain and ~/.netrc into the fresh ISO; genix ships GEHACK's
            # keys instead.
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
            # and the org's SSH keys. Dead weight in a private practice VM.
            users.users.gehack = {
              hashedPassword = lib.mkForce "!";
              extraGroups = lib.mkForce [];
              openssh.authorizedKeys.keyFiles = lib.mkForce [];
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
      # 127.0.0.1:2223 forwards to the guest's sshd, for copying the TRD
      # toolchain and ~/.netrc in after each fresh start.
      script = ''
        exec ${pkgs.qemu_kvm}/bin/qemu-system-x86_64 \
          -name genix -machine q35,accel=kvm -cpu host -smp 4 -m 8G \
          -drive file="$(echo ${genix.system.build.isoImage}/iso/*.iso)",media=cdrom,readonly=on \
          -vga none -device virtio-vga,xres=1920,yres=1080 \
          -device qemu-xhci -device usb-tablet \
          -nic user,model=virtio-net-pci,hostfwd=tcp:127.0.0.1:2223-:22 \
          -display none -spice addr=127.0.0.1,port=${toString spicePort},disable-ticketing=on
      '';
    };
  };
}
