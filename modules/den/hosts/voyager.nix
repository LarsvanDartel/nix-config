# voyager (x86_64 desktop/gaming laptop, ThinkPad P1 gen3 + nvidia). den-produced;
# named `voyagerd` during the migration to avoid colliding with the old `voyager`.
#
# Hardware from a nixos-facter report; filesystems from disko. Generate on voyager:
#   sudo nix run nixpkgs#nixos-facter -- -o modules/den/hosts/_facter/voyager.facter.json
#
{
  den,
  inputs,
  ...
}: {
  den.hosts.x86_64-linux.voyagerd = {
    hostName = "voyager";
    users.lvdar = {};
  };

  den.aspects.voyagerd = {
    includes = with den.aspects; [
      core.boot
      core.impermanence
      roles.desktop
      roles.gaming
      desktop.hyprland
      desktop.tuigreet
      services.containers
      services.suwayomi
      hardware.fingerprint
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

    nixos = {...}: {
      imports = [
        inputs.nixos-facter-modules.nixosModules.facter
        {facter.reportPath = ./_facter/voyager.facter.json;}
        inputs.nixos-hardware.nixosModules.lenovo-thinkpad-p1-gen3
        inputs.nixos-hardware.nixosModules.common-gpu-nvidia
        inputs.disko.nixosModules.disko
        (import ../../hosts/voyager/_hw/disko.nix {device = "/dev/nvme0n1";})
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
      };

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

      system.stateVersion = "24.11";
    };
  };
}
