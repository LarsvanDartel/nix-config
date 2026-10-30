# voyager (x86_64 laptop; hardware profile in _hw/voyager/, see `hardwareProfile` below). den-produced.
#
# Hardware from a nixos-facter report; filesystems from disko. Generate on voyager:
#   sudo nix run nixpkgs#nixos-facter -- -o modules/den/hosts/_facter/voyager.facter.json
{
  den,
  inputs,
  ...
}: let
  # The machine voyager currently is: "thinkpad-p1" or "framework-12".
  # Switching is a runbook: docs/src/install.md, "Moving voyager to the Framework 12".
  # Static data, not a config read, so it may choose includes. Not named
  # `hardware`: that would shadow den.aspects.hardware inside `with den.aspects`.
  hardwareProfile = "thinkpad-p1";
  profiles = {
    thinkpad-p1 = {
      includes = with den.aspects.hardware; [thinkpad fingerprint];
      module = import ./_hw/voyager/thinkpad-p1.nix {inherit inputs;};
    };
    framework-12 = {
      includes = [];
      module = import ./_hw/voyager/framework-12.nix {inherit inputs;};
    };
  };
  profile = profiles.${hardwareProfile};
in {
  den.hosts.x86_64-linux.voyager = {
    users.lvdar = {};
    meshAddress = "100.68.60.163";
    sshHostKey = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIDVfDaFhgvfE2K47EGx8P+eL6od9H/oFKQZNeXvfr6Uh";
  };

  den.aspects.voyager = {
    includes = with den.aspects;
      [
        core.boot
        core.impermanence
        roles.desktop
        roles.gaming
        desktop.niri
        desktop.greetd.noctalia
        desktop.tablet
        services.containers
        services.netbird.client
        services.netbird-gewis
        services.eduvpn
        # Not node-exporter: a sleeping laptop would sit permanently "target down".
        services.alloy
      ]
      # Here, not appended: include order sets the order of merged `lines`
      # options such as boot.extraModprobeConfig.
      ++ profile.includes
      ++ [
        services.remote-builder.client
        hardware.v4l2loopback
      ];

    provides.lvdar = {
      includes = with den.aspects; [
        roles.desktop-home
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
        home.rbw
        home.remmina
        home.xournalpp
        home.rnote
        home.krita
      ];

      homeManager = {
        pkgs,
        lib,
        ...
      }: {
        cosmos = {
          # iDRAC's OpenSSH 6.6 can't parse ed25519 — hence an RSA identity.
          # 2048 bits: iDRAC 7/8 rejects 4096-bit keys (Dell KB 000142481).
          # Merges with lvdar.nix's device key.
          cli.programs.ssh.identities = ["idrac"];

          cli.programs.yazi.defaultApplication = true;

          desktops.wallpapers.rotate.count = 20;

          gaming.launchers.minecraft.mcsr.enable = true;

          programs = {
            zathura.defaultApplication = true;
            mpv.defaultApplication = true;
            thunderbird.defaultApplication = true;
            obs-studio = {
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

        # A jump through pioneer: the BMC's sshd must only be reachable from
        # the host in front of it.
        programs.ssh.settings."idrac" = lib.hm.dag.entryBefore ["*"] {
          HostName = "192.168.2.111";
          ProxyJump = "pioneer";

          # No User: the BMC account shares the local username.
          IdentityFile = "~/.ssh/id_idrac";
          IdentitiesOnly = true;

          # BMC OpenSSH 6.6 can only sign SHA-1 ssh-rsa.
          PubkeyAcceptedAlgorithms = "+ssh-rsa";
          HostKeyAlgorithms = "+ssh-rsa";

          # Silences only the permanent post-quantum warning; blanket `no` would
          # hide future weak-crypto warnings too.
          WarnWeakCrypto = "no-pq-kex";

          # Two slow handshake hops per command; re-enable multiplexing here
          # (disabled globally).
          ControlMaster = "auto";
          ControlPersist = "10m";
        };
      };
    };

    nixos = {lib, ...}: {
      imports = [
        inputs.nixos-facter-modules.nixosModules.facter
        {facter.reportPath = ./_facter/voyager.facter.json;}
        profile.module
        inputs.disko.nixosModules.disko
        (import ./_hw/voyager/disko.nix {device = "/dev/nvme0n1";})
      ];

      cosmos = {
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

      # A laptop joins foreign networks: sshd only over the mesh.
      services.openssh.openFirewall = false;
      cosmos.services.netbird.client.exposedPorts = [2222];

      boot = {
        kernelParams = ["quiet"];
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

      # Minecraft.
      networking.firewall.allowedUDPPorts = [25565];
      networking.firewall.allowedTCPPorts = [25565];

      cosmos.system.impermanence.device = "/dev/mapper/crypted";

      cosmos.profiles.desktop.addons.greetd.noctalia.defaultSession = "niri";

      # Boot-time choice; specialisation bodies can't `include` den aspects, so Umbriel comes from the _umbriel factories. nh 4.4.1 reads /etc/specialisation to stay in the booted one. Without configurationName GRUB dates every entry 1970-01-01.
      specialisation.umbriel.configuration = {
        boot.loader.grub.configurationName = "umbriel + noctalia";
        environment.etc.specialisation.text = "umbriel";
        imports = [(import ../aspects/desktop/_umbriel/system.nix {})];
        # The entry's Name= (and DesktopNames=) is "Umbriel".
        cosmos.profiles.desktop.addons.greetd.noctalia.defaultSession = lib.mkForce "Umbriel";
        home-manager.users.lvdar.imports = [(import ../aspects/home/desktop/_umbriel/home.nix {})];
      };

      # Push the desktop closure and pioneer's toplevel (built on endeavour,
      # copied back here) so CI needn't rebuild them.
      cosmos.services.attic.client.watchStore.enable = true;

      system.stateVersion = "24.11";
    };
  };
}
