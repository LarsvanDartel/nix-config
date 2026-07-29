# voyager (x86_64 desktop/gaming laptop, ThinkPad P1 gen3 + nvidia). den-produced;
# named `voyager` during the migration to avoid colliding with the old `voyager`.
#
# Hardware from a nixos-facter report; filesystems from disko. Generate on voyager:
#   sudo nix run nixpkgs#nixos-facter -- -o modules/den/hosts/_facter/voyager.facter.json
#
{
  den,
  inputs,
  ...
}: {
  den.hosts.x86_64-linux.voyager.users.lvdar = {};

  den.aspects.voyager = {
    includes = with den.aspects; [
      core.boot
      core.impermanence
      roles.desktop
      roles.gaming
      desktop.hyprland
      desktop.greetd.tuigreet
      # Base-level, not specialisation-level: the niri specialisation inherits
      # the parent config, so the Mod-tap option has to be declared here for its
      # binds to read it.
      desktop.keyd
      services.containers
      services.netbird.client
      services.suwayomi
      hardware.fingerprint
      hardware.thinkpad
      hardware.v4l2loopback
    ];

    # the primary user gets the desktop home + the voyager-specific apps.
    lvdar = {
      includes = with den.aspects; [
        roles.desktop-home
        home.steam
        home.minecraft
        home.claude
        home.taskwarrior
        home.zathura
        home.thunderbird
        home.libreoffice
        home.zotero
        home.obs-studio
        home.which-key
        home.freecad
        home.orca-slicer
        home.simplelogin
        home.pangolin
        home.proton.mail-bridge
        home.proton.mail-desktop
        home.proton.pass-cli
        home.proton.vpn-cli
      ];

      # voyager-specific home settings.
      homeManager = {pkgs, ...}: {
        cosmos = {
          cli.programs.nvim.languages = {
            rust.enable = true;
            clang.enable = true;
            typst.enable = true;
            python.enable = true;
            rocq.enable = true;
            formal.enable = true;
            mcrl2.enable = true;
          };

          desktops.hyprland.animations.enable = false;

          gaming.launchers.minecraft.mcsr.enable = true;

          programs = {
            zathura.defaultApplication = true;
            obs-studio = {
              cudaSupport = true;
              plugins = with pkgs.obs-studio-plugins; [
                advanced-scene-switcher
                input-overlay
                obs-advanced-masks
                obs-backgroundremoval
                obs-composite-blur
                obs-move-transition
                obs-source-clone
                obs-source-record
                obs-stroke-glow-shadow
                obs-tuna
                obs-mute-filter
                obs-pipewire-audio-capture
                obs-vkcapture
                obs-vaapi
                wlrobs
                droidcam-obs
              ];
            };
          };

          system.impermanence.persist.directories = [
            "nix-config"
            "nix-secrets"
            "dev"
            "school"
            "Videos"
            ".config/Code"
            "balatro"
          ];
        };

        programs.ssh.settings."es-pynq047.ics.ele.tue.nl".setEnv = "TERM=xterm-256color";

        home.packages = [pkgs.mcrl2];
      };
    };

    nixos = {lib, ...}: {
      imports = [
        inputs.nixos-facter-modules.nixosModules.facter
        {facter.reportPath = ./_facter/voyager.facter.json;}
        inputs.nixos-hardware.nixosModules.lenovo-thinkpad-p1-gen3
        inputs.nixos-hardware.nixosModules.common-gpu-nvidia
        inputs.disko.nixosModules.disko
        (import ./_hw/voyager/disko.nix {device = "/dev/nvme0n1";})
      ];

      cosmos = {
        system.boot.detect-windows = true;

        services.suwayomi = {
          basicAuth.enable = true;
          webview.enable = true;
          downloadsDir = "/var/lib/suwayomi-downloads";
          homeLink = "/home/lvdar/manga";
        };

        hardware.v4l2loopback.devices = [
          {
            number = 1;
            label = "OBS Virtual Camera";
          }
        ];

        cli.programs.nh.flake-dir = "/home/lvdar/nix-config";

        # suwayomi.lvdar.nl is published from voyager, not endeavour, so the
        # edge target lands here.
        services.netbird.client.exposedPorts = [8080];
      };

      # nixos-facter puts every detected GPU driver into the initrd. Here that
      # means nvidia, which drags in 103 MB of GSP firmware plus a 12 MB
      # nvidia.ko and takes the initrd to 138 MB — three of those fill the
      # 511 MB ESP on their own, which is what made `nh os boot` run out of
      # space. Nothing needs it that early: the boot console and the LUKS
      # prompt are on the internal panel, which is Intel, and nvidia loads at
      # stage 2 via boot.kernelModules (nvidia_uvm) as before.
      facter.detected.boot.graphics.kernelModules = ["i915"];

      # Hibernate
      boot = {
        kernelParams = ["resume_offset=533760"];
        resumeDevice = "/dev/disk/by-uuid/c2dc9bb7-f815-4c9c-bd96-68bebb100aef";
        extraModprobeConfig = ''
          options iwlwifi power_save=0 uapsd_disable=1
          options iwlmvm power_scheme=1

          # NuPhy Air75 registers as an Apple keyboard; fnmode=0 makes the top row
          # act as plain F1-F12 without needing Fn, fixing Fn key combos.
          options hid_apple fnmode=0
        '';
      };

      hardware.nvidia = {
        open = true;
        powerManagement = {
          enable = true;
          finegrained = true;
        };
        prime.offload = {
          enable = true;
          enableOffloadCmd = true;
        };
      };

      networking.networkmanager.wifi.powersave = false;
      environment.etc."NetworkManager/conf.d/wifi.conf".text = ''
        [connection]
        wifi.powersave = 2

        [device]
        wifi.scan-rand-mac-address = no
      '';
      networking.wireless.extraConfig = ''
        bgscan=""
      '';

      networking.firewall.allowedUDPPorts = [25565];
      networking.firewall.allowedTCPPorts = [25565];

      cosmos.system.impermanence.device = "/dev/mapper/crypted";

      # Compositor choice is a BOOT-time switch: each specialisation is its own
      # GRUB entry. The default entry stays Hyprland, so nothing changes unless
      # a specialisation is picked.
      #
      # Specialisation bodies are plain NixOS modules and cannot `include` den
      # aspects, so the niri/noctalia content is applied from the shared factory
      # modules that the aspects also use.
      # `nh os switch` reads /etc/specialisation to stay in the specialisation
      # you booted (nh 4.4.1, SPEC_LOCATION); NixOS itself never writes that
      # file, so each specialisation declares its own name here. The base config
      # deliberately has no such file, so it resolves to the parent system.
      specialisation = {
        # Explicit, labelled entry, otherwise identical to the default.
        hyprland.configuration.environment.etc.specialisation.text = "hyprland";

        niri.configuration = {
          imports = [
            (import ../aspects/desktop/_niri/system.nix {inherit inputs;})
            # Swap tuigreet for the noctalia greeter, so the login screen
            # matches the shell this specialisation boots into.
            (import ../aspects/desktop/_greetd/noctalia.nix {})
          ];

          environment.etc.specialisation.text = "niri";

          cosmos.profiles.desktop.addons.greetd.noctalia.defaultSession = "niri";

          # Hyprland and niri must not both own the session.
          programs.hyprland.enable = lib.mkForce false;

          home-manager.users.lvdar = {
            imports = [
              (import ../aspects/home/desktop/_noctalia/home.nix {inherit inputs;})
              (import ../aspects/desktop/_niri/home.nix {})
            ];

            # noctalia replaces the Hyprland-era shell pieces.
            wayland.windowManager.hyprland.enable = lib.mkForce false;
            programs.waybar.enable = lib.mkForce false;
            programs.hyprlock.enable = lib.mkForce false;
            programs.rofi.enable = lib.mkForce false;
            services.mako.enable = lib.mkForce false;
            services.hyprpaper.enable = lib.mkForce false;
          };
        };
      };

      # QEMU emulation so aarch64 derivations (e.g. the pioneer Pi toplevel) can
      # be built locally on this x86_64 machine. Slow, but avoids needing the Pi
      # as a remote builder.
      boot.binfmt.emulatedSystems = ["aarch64-linux"];

      system.stateVersion = "24.11";
    };
  };
}
