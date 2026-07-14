{config, ...}: let
  nixos = config.flake.modules.nixos;
  home = config.flake.modules.homeManager;
in {
  configurations.voyager = {
    system = "x86_64-linux";
    module = {
      inputs,
      config,
      ...
    }: let
      # Use a nixos-facter report if present, otherwise the committed
      # hardware-configuration.nix. Generate: nixos-facter -o modules/hosts/voyager/_hw/voyager.facter.json
      hardware =
        if builtins.pathExists ./_hw/voyager.facter.json
        then [
          inputs.nixos-facter-modules.nixosModules.facter
          {facter.reportPath = ./_hw/voyager.facter.json;}
        ]
        else [./_hw/hardware-configuration.nix];
    in {
      imports =
        (with nixos; [
          common
          desktop
          gaming
          hyprland
          tuigreet
          impermanence
          containers
          suwayomi
          fingerprint
          v4l2loopback
        ])
        ++ hardware
        ++ [
          inputs.nixos-hardware.nixosModules.lenovo-thinkpad-p1-gen3
          inputs.nixos-hardware.nixosModules.common-gpu-nvidia
          inputs.disko.nixosModules.disko
          (import ./_hw/disko.nix {device = "/dev/nvme0n1";})
        ];

      # Hibernate
      boot = {
        kernelParams = [
          "resume_offset=533760"
        ];
        resumeDevice = "/dev/disk/by-uuid/c2dc9bb7-f815-4c9c-bd96-68bebb100aef";
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
      boot.extraModprobeConfig = ''
        options iwlwifi power_save=0 uapsd_disable=1
        options iwlmvm power_scheme=1

        # NuPhy Air75 registers as an Apple keyboard; fnmode=0 makes the top row
        # act as plain F1-F12 without needing Fn, fixing Fn key combos.
        options hid_apple fnmode=0
      '';

      cosmos = {
        system.boot.detect-windows = true;

        services.suwayomi = {
          basicAuth.enable = true;
          webview.enable = true;
          downloadsDir = "/var/lib/suwayomi-downloads";
          homeLink = "/home/${config.cosmos.user.name}/manga";
        };

        # Virtual camera target for OBS (Start Virtual Camera).
        hardware.v4l2loopback.devices = [
          {
            number = 1;
            label = "OBS Virtual Camera";
          }
        ];

        cli.programs.nh.flake-dir = "/home/${config.cosmos.user.name}/nix-config";
      };

      networking.firewall.allowedUDPPorts = [25565];
      networking.firewall.allowedTCPPorts = [25565];

      # Host-specific home (base + desktop are wired centrally by the aggregates).
      home-manager.users.lvdar = {pkgs, ...}: {
        imports = with home; [
          hyprland
          simplelogin
          claude
          pangolin
          which-key
          taskwarrior
          orca-slicer
          freecad
          minecraft
          steam
          zathura
          libreoffice
          zotero
          obs-studio
          thunderbird
          proton-mail-bridge
          proton-mail-desktop
          proton-pass-cli
          proton-vpn-cli
        ];

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

        programs.ssh.settings = {
          "es-pynq047.ics.ele.tue.nl" = {
            setEnv = "TERM=xterm-256color";
          };
        };

        home.packages = [pkgs.mcrl2];
      };

      system.stateVersion = "24.11";
    };
  };
}
