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
      services.eduvpn
      # Ships its journal to loki. Not node-exporter: a laptop that sleeps
      # would sit permanently "target down". Logs have no such problem —
      # they simply stop and resume.
      services.alloy
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
        home.catt
        home.zathura
        home.thunderbird
        home.libreoffice
        home.zotero
        home.obs-studio
        home.which-key
        home.freecad
        home.orca-slicer
        home.simplelogin
        home.proton.mail-bridge
        home.proton.mail-desktop
        home.proton.pass-cli
        home.proton.vpn-cli
        home.eduvpn
      ];

      # voyager-specific home settings.
      homeManager = {pkgs, ...}: {
        cosmos = {
          # The file manager for inode/directory.
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

            # Here and not in the nvim aspect: it needs endeavour's ollama on
            # the mesh, so it is a property of this machine's reachability
            # rather than of the editor. Manual trigger — see the option — so
            # that being off the mesh costs a keypress rather than a stall on
            # every pause.
            minuet.enable = true;
          };

          desktops.hyprland.animations.enable = false;

          # Rotate through the top 20 of the ranked collection rather than the
          # default 8. This is the machine the collection was ranked on and the
          # one it is looked at all day, so the cycle can afford to be longer
          # before it starts repeating; 20 of 90 still leaves the ones that lost
          # out of it, which was the point of ranking them.
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

        hardware.v4l2loopback.devices = [
          {
            number = 1;
            label = "OBS Virtual Camera";
          }
        ];

        cli.programs.nh.flake-dir = "/home/lvdar/nix-config";

        # Sync against endeavour's taskchampion-sync-server over the mesh,
        # rather than through gaia at task.lvdar.nl the way the phone does.
        # Same history either way — this path just declines to leave the mesh
        # and come back in to reach a machine two rooms away. The id and the
        # encryption secret come from sops; see the aspect.
        programs.taskwarrior.sync.serverUrl = "http://endeavour.nb.lvdar.nl:10222";
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

      # DNS on a laptop that roams onto networks it does not control.
      #
      # The global default pins 9.9.9.9 as resolvconf's `static` entry, which
      # makes it the *first* nameserver everywhere and, because
      # `nameservers != []`, also flips NetworkManager to `dns = "none"` — so NM
      # never installs the DNS the network itself handed out. On TU/e's
      # tue-wpa2 that is fatal: Quad9's :53 does not answer from campus, and the
      # resolvers that would (131.155.3.3/131.155.2.3) only reached resolv.conf
      # at all because dhcpcd was *also* running on the wifi interface. Empty
      # here means NM owns DNS and the local network's resolvers are used, which
      # is the only thing that works on a network that filters egress :53.
      cosmos.networking.nameservers = [];

      # ...and with NM owning DHCP, dhcpcd must not also be. dhcpcd was leasing
      # wlp0s20f3 alongside NetworkManager's internal DHCP client — two clients
      # leasing, writing resolv.conf and adding routes on one interface. It only
      # ever looked harmless because dhcpcd happened to win the resolv.conf
      # race, which is also the only reason DNS worked at all while
      # `nameservers` above forced NM to `dns = "none"`.
      #
      # Disabled here rather than via `networking.useDHCP`: the facter module
      # declares `networking.interfaces.wlp0s20f3.useDHCP = true` per-interface,
      # and dhcpcd's own default is the *or* of the global flag and every
      # interface's, so clearing the global one changes nothing.
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

      # 25565 is a Minecraft server run here occasionally, for people on the
      # same network.
      #
      # 5353 and 45114 are what home.catt needs, and are the reason `catt scan`
      # found four devices with the firewall stopped and none with it running.
      # Chromecast discovery is mDNS: the query goes to the multicast group and
      # the replies come back unsolicited, so with nothing opened they are
      # dropped and the scan reports an empty network rather than an error.
      # 45114 is the little web server catt starts when casting a *local file* —
      # the device is handed a URL pointing back here and fetches it itself, so
      # without that port a scan succeeds, the cast is accepted, and the video
      # never starts.
      #
      # Open on every interface rather than the wireless one alone, which reads
      # careless and is close to it: this is a laptop, so the untrusted network
      # is the same interface as the trusted one and scoping buys nothing
      # against a café. What it would exclude is wt0, and the mesh already
      # refuses this by policy — a non-fleet peer gets DNS and nothing else, and
      # no fleet machine is looking for a Chromecast.
      #
      # The exposure is bounded by nothing listening most of the time: a port
      # opened in the firewall with no process behind it refuses connections.
      # It matters only while catt is running, and then it is one file, being
      # served to a device on the same network, for as long as it plays.
      networking.firewall.allowedUDPPorts = [25565 5353];
      networking.firewall.allowedTCPPorts = [25565 45114];

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
      # `configurationName` is what GRUB calls the entry. Without it
      # install-grub.pl falls back to "(<name> - <date> - <version>)", where
      # the date comes from lstat()ing a *store* symlink — so every
      # specialisation is dated 1970-01-01 and the real label is buried in
      # parentheses behind it. The result is unreadable at boot, which is the
      # one moment it has to be readable.
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

      # Push what this machine builds to the cache, which is most of what the
      # fleet builds: the desktop closure, everything from the overlays, and
      # the emulated aarch64 toplevel above — the expensive one this exists
      # for. Until now nothing anywhere pushed, so the cache was empty and CI
      # rebuilt from source what this laptop had already emulated.
      cosmos.services.attic.client.watchStore.enable = true;

      system.stateVersion = "24.11";
    };
  };
}
