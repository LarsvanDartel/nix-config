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
      # Base-level, not specialisation-level: the niri specialisation
      # inherits the parent config, so the Mod-tap option must be declared
      # here for its binds to read.
      desktop.keyd
      services.containers
      services.netbird.client
      services.eduvpn
      # Ships its journal to loki. Not node-exporter: a sleeping laptop
      # would sit permanently "target down"; logs just stop and resume.
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
        home.proton.mail-bridge
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

            # Here, not in the nvim aspect: it needs endeavour's ollama on
            # the mesh — a property of this machine's reachability. Manual
            # trigger (see the option) so being off the mesh costs a
            # keypress, not a stall on every pause.
            minuet.enable = true;
          };

          desktops.hyprland.animations.enable = false;

          # Top 20 of the ranked collection rather than the default 8: this
          # is the machine it is looked at on all day, and 20 of 90 still
          # leaves the losers out — which was the point of ranking them.
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

        # Sync direct over the mesh rather than out through gaia and back;
        # same history either way. Credentials from sops — see the aspect.
        programs.taskwarrior.sync.serverUrl = "http://endeavour.nb.lvdar.nl:10222";
      };

      # facter would put nvidia in the initrd — 103 MB of GSP firmware plus
      # nvidia.ko; three of those fill the 511 MB ESP (what made `nh os boot`
      # run out of space). Console and LUKS prompt are on the Intel panel;
      # nvidia loads at stage 2 via boot.kernelModules as before.
      facter.detected.boot.graphics.kernelModules = ["i915"];

      # Hibernate
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

        # Plymouth gives the LUKS FIDO2 prompt a real UI instead of a
        # plain-text line racing kernel boot spam; `quiet` keeps log lines
        # off the splash.
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

      # Disk swap was sitting at 15.8/16G under normal desktop load (default
      # swappiness=60, no zram) — thrashing to the 990 Pro well before RAM was
      # actually exhausted. zram-generator's default priority (5) beats the
      # disko swapfile's (-2), so the kernel drains this RAM-backed, zstd
      # -compressed tier first and only spills to disk once ~7.5G (50% of
      # 15G RAM) of compressed pages is full. Raising swappiness makes the
      # kernel reach for that now-cheap tier instead of reclaiming page
      # cache; it does *not* touch the disk swapfile, which stays the
      # hibernation target (boot.resumeDevice/resume_offset above) and is
      # never written to directly by zram.
      zramSwap.enable = true;
      boot.kernel.sysctl."vm.swappiness" = 100;

      # The global default pins 9.9.9.9 first in resolv.conf and flips NM
      # to dns = none, so the network's own resolvers never arrive — fatal
      # on TU/e's tue-wpa2, where Quad9's :53 is filtered. Empty means NM
      # owns DNS and uses the local network's resolvers: the only thing that
      # works where egress :53 is filtered.
      cosmos.networking.nameservers = [];

      # ...and with NM owning DHCP, dhcpcd must not also be leasing
      # wlp0s20f3 — two clients on one interface, and DNS only ever worked
      # because dhcpcd happened to win the resolv.conf race. Disabled here,
      # not via networking.useDHCP: facter declares per-interface useDHCP
      # and dhcpcd ORs the global flag with every interface's, so the global
      # changes nothing.
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

      # 25565: an occasional Minecraft server for people on the same
      # network. 5353/45114: catt — mDNS replies come back unsolicited
      # (dropped means `catt scan` reports an empty network, not an error),
      # and 45114 is the server catt starts when casting a local file (the
      # device fetches the URL itself; without it the cast is accepted and
      # the video never starts). Open on every interface: on a laptop
      # scoping buys nothing, and wt0 is already refused by mesh policy.
      # Bounded by nothing listening most of the time.
      networking.firewall.allowedUDPPorts = [25565 5353];
      networking.firewall.allowedTCPPorts = [25565 45114];

      cosmos.system.impermanence.device = "/dev/mapper/crypted";

      # Compositor choice is a boot-time switch: each specialisation is its
      # own GRUB entry; the default stays Hyprland. Specialisation bodies
      # are plain NixOS modules and can't `include` den aspects, so the
      # niri/noctalia content comes from the shared factory modules.
      # `nh os switch` reads /etc/specialisation to stay in the booted one
      # (nh 4.4.1) — NixOS never writes that file, so each specialisation
      # declares its own name here. configurationName is what GRUB shows;
      # without it every entry is dated 1970-01-01 (lstat of a store
      # symlink) and unreadable at the one moment it must be readable.
      specialisation = {
        # Explicit, labelled entry, otherwise identical to the default.
        hyprland.configuration = {
          environment.etc.specialisation.text = "hyprland";
          boot.loader.grub.configurationName = "Hyprland";
        };

        niri.configuration = {
          boot.loader.grub.configurationName = "niri + noctalia";

          imports = [
            (import ../aspects/desktop/_niri/system.nix {inherit inputs;})
            # Swap tuigreet for the noctalia greeter, matching the shell
            # booted.
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

      # Push what this machine builds — the desktop closure, the overlays,
      # and the emulated aarch64 toplevel (the expensive one). Before this
      # nothing pushed, so CI rebuilt from source what this laptop had
      # already emulated.
      cosmos.services.attic.client.watchStore.enable = true;

      system.stateVersion = "24.11";
    };
  };
}
