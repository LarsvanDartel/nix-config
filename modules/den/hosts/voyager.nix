# voyager (x86_64 desktop/gaming laptop, ThinkPad P1 gen3 + nvidia). den-produced.
#
# Hardware from a nixos-facter report; filesystems from disko. Generate on voyager:
#   sudo nix run nixpkgs#nixos-facter -- -o modules/den/hosts/_facter/voyager.facter.json
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
      # Base-level, not specialisation-level: niri inherits the parent config
      # and its binds read the Mod-tap option.
      desktop.keyd
      services.containers
      services.netbird.client
      services.eduvpn
      # Not node-exporter: a sleeping laptop would sit permanently "target down".
      services.alloy
      hardware.fingerprint
      hardware.thinkpad
      hardware.v4l2loopback
    ];

    lvdar = {
      includes = with den.aspects; [
        roles.desktop-home
        home.steam
        home.minecraft
        home.tino
        home.kanidm
        home.mcrl2
        home.claude
        home.oh-my-pi
        home.taskwarrior
        home.catt
        home.zathura
        home.thunderbird
        home.libreoffice
        home.zotero
        home.process-mining
        home.obs-studio
        home.which-key
        # home.freecad
        home.orca-slicer
        home.simplelogin
        home.proton.pass-cli
        home.proton.vpn-cli
        home.eduvpn
      ];

      homeManager = {pkgs, ...}: {
        cosmos = {
          cli.programs.yazi.defaultApplication = true;

          cli.programs.nvim = {
            languages = {
              rust.enable = true;
              clang.enable = true;
              typst.enable = true;
              python.enable = true;
              rocq.enable = true;
              formal.enable = true;
              mcrl2.enable = true;
            };

            # Needs endeavour's ollama on the mesh; manual trigger so being off
            # the mesh costs a keypress, not a stall on every pause.
            minuet.enable = true;
          };

          desktops.hyprland.animations.enable = false;

          desktops.wallpapers.rotate.count = 20;

          gaming.launchers.minecraft.mcsr.enable = true;

          programs = {
            zathura.defaultApplication = true;
            mpv.defaultApplication = true;
            thunderbird.defaultApplication = true;
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

        hardware.v4l2loopback.devices = [
          {
            number = 1;
            label = "OBS Virtual Camera";
          }
        ];

        cli.programs.nh.flake-dir = "/home/lvdar/nix-config";

        # Direct over the mesh rather than through gaia; creds from sops.
        programs.taskwarrior.sync.serverUrl = "http://endeavour.nb.lvdar.nl:10222";
      };

      # Keep nvidia (103 MB GSP firmware) out of the initrd: three copies
      # filled the 511 MB ESP. nvidia loads at stage 2.
      facter.detected.boot.graphics.kernelModules = ["i915"];

      boot = {
        kernelParams = ["resume_offset=533760" "quiet"];
        resumeDevice = "/dev/disk/by-uuid/c2dc9bb7-f815-4c9c-bd96-68bebb100aef";
        extraModprobeConfig = ''
          options iwlwifi power_save=0 uapsd_disable=1
          options iwlmvm power_scheme=1

          # NuPhy Air75 registers as an Apple keyboard; fnmode=0 makes the top row
          # act as plain F1-F12 without needing Fn, fixing Fn key combos.
          options hid_apple fnmode=0
        '';

        # Plymouth gives the LUKS FIDO2 prompt a real UI.
        plymouth.enable = true;
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

      # Disk swap was thrashing at 15.8/16G before RAM was exhausted. zram's
      # priority (5) beats the swapfile's (-2), so it fills first; the
      # swapfile stays the hibernation target.
      zramSwap.enable = true;
      boot.kernel.sysctl."vm.swappiness" = 100;

      # Empty: NM owns DNS and uses the network's resolvers. The global
      # default (9.9.9.9) breaks on TU/e's tue-wpa2, where Quad9's :53 is filtered.
      cosmos.networking.nameservers = [];

      # ...and dhcpcd must not also lease wlp0s20f3. Not via
      # networking.useDHCP: facter sets per-interface useDHCP, which dhcpcd ORs in.
      networking.dhcpcd.enable = false;

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

      # 25565: Minecraft. 5353: catt mDNS replies (dropped = empty scan).
      # 45114: catt local-file cast server (without it the video never starts).
      networking.firewall.allowedUDPPorts = [25565 5353];
      networking.firewall.allowedTCPPorts = [25565 45114];

      cosmos.system.impermanence.device = "/dev/mapper/crypted";

      # Specialisation bodies can't `include` den aspects; niri content comes
      # from the factory modules. nh 4.4.1 reads /etc/specialisation to stay
      # in the booted one (NixOS never writes it). Without configurationName
      # GRUB dates every entry 1970-01-01.
      specialisation = {
        hyprland.configuration = {
          environment.etc.specialisation.text = "hyprland";
          boot.loader.grub.configurationName = "Hyprland";
        };

        niri.configuration = {
          boot.loader.grub.configurationName = "niri + noctalia";

          imports = [
            (import ../aspects/desktop/_niri/system.nix {inherit inputs;})
            # noctalia greeter to match the shell.
            (import ../aspects/desktop/_greetd/noctalia.nix {})
          ];

          environment.etc.specialisation.text = "niri";

          cosmos.profiles.desktop.addons.greetd.noctalia.defaultSession = "niri";

          programs.hyprland.enable = lib.mkForce false;

          home-manager.users.lvdar = {
            imports = [
              (import ../aspects/home/desktop/_noctalia/home.nix {inherit inputs;})
              (import ../aspects/desktop/_niri/home.nix {})
            ];

            wayland.windowManager.hyprland.enable = lib.mkForce false;
            programs.waybar.enable = lib.mkForce false;
            programs.hyprlock.enable = lib.mkForce false;
            programs.rofi.enable = lib.mkForce false;
            services.mako.enable = lib.mkForce false;
            services.hyprpaper.enable = lib.mkForce false;
          };
        };
      };

      # Build aarch64 (pioneer) locally under QEMU.
      boot.binfmt.emulatedSystems = ["aarch64-linux"];

      # Push the desktop closure and the emulated aarch64 toplevel so CI
      # needn't rebuild them.
      cosmos.services.attic.client.watchStore.enable = true;

      system.stateVersion = "24.11";
    };
  };
}
