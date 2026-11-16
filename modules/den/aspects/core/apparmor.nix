# core.apparmor — AppArmor with apparmor.d profiles (one state for every policy, complain for now) and the NixOS adaptations they need.
{...}: {
  den.aspects.core.apparmor.nixos = {
    config,
    lib,
    pkgs,
    ...
  }: let
    inherit (lib.options) mkOption;
    inherit (lib.types) enum listOf str;

    cfg = config.cosmos.security.apparmor;
    openssh = config.services.openssh.package;

    # Reached by name from local/sshd*, never by path (NixOS has no libexec/openssh/), so match.py cannot list them.
    sshChain = ["sshd-session" "sshd-auth" "sftp-server"];
    baseline =
      if cfg.coverage == "installed"
      then import ./_apparmor/common.nix ++ sshChain
      else import ./_apparmor/daemons.nix;

    excluded = [
      # Full-system policy (PID 1, user managers, systemd-executor): out of scope.
      "sd"
      "sd-mount"
      "sd-umount"
      "sdu"
      "systemd"
      "systemd-user"
      # Attached by AppArmorProfile= unit drop-ins, and dbus-broker has no AppArmor mediation.
      "dbus-system"
      "dbus-session"
      # Name collisions: an unrelated bin/orca; the parser apparmor.service itself runs.
      "orca"
      "apparmor_parser"
      # Still "conflicting x modifiers" on store paths after the package's priority fix.
      "aa-notify"
      "bitwarden"
      "claude"
      "claude-desktop"
      "code"
      "discord"
      "dolphin"
      "element-desktop"
      "exo-open"
      "freetube"
      "gio-launch-desktop"
      "linuxqq"
      "mullvad-gui"
      "protonmail"
      "session-desktop"
      "signal-desktop"
      "spotify"
      "superproductivity"
      "vesktop"
      "wechat"
      "wechat-appimage"
      "wechat-universal"
      "xdg-email"
      "xdg-open"
    ];
  in {
    options.cosmos.security.apparmor = {
      state = mkOption {
        type = enum ["complain" "enforce"];
        default = "complain";
        description = "Mode for every apparmor.d and hand-written policy.";
      };
      coverage = mkOption {
        type = enum ["installed" "daemons"];
        default = "installed";
        description = ''
          `installed`: every apparmor.d profile matching software on the host (core/_apparmor/common.nix plus the host's list).
          `daemons`: only running daemons and the privilege boundary, for hosts too slow to parse ~250 profiles each boot.
        '';
      };
      profiles = mkOption {
        type = listOf str;
        default = [];
        description = "Host-specific apparmor.d profile names, on top of the coverage baseline.";
      };
      disabledProfiles = mkOption {
        type = listOf str;
        default = [];
        description = "apparmor.d profile names to drop on this host.";
      };
    };

    config = {
      security.apparmor = {
        enable = true;
        # Before nixpkgs' apparmor-profiles: apparmor.d's tunables/*.d must win the include search.
        packages = lib.mkBefore [pkgs.apparmor-d];
        policies = lib.genAttrs (lib.subtractLists (excluded ++ cfg.disabledProfiles) (lib.unique (baseline ++ cfg.profiles))) (name: {
          inherit (cfg) state;
          path = "${pkgs.apparmor-d}/etc/apparmor.d/${name}";
        });
        includes = {
          # Complain mode still enforces explicit deny rules; these only widen.
          "abstractions/base-strict.d/nixos" = ''
            /nix/store/** r,
            /nix/store/*/{bin,sbin,lib,lib64,libexec}/** mr,
            /nix/store/*/{bin,sbin,libexec}/{,**/}.*-wrapped{,_} mrix,
          '';
          "local/sshd" = ''
            ${openssh}/libexec/sshd-session px -> sshd-session,
          '';
          "local/sshd-session" = ''
            ${openssh}/libexec/sshd-auth px -> sshd-auth,
            ${openssh}/libexec/sftp-server px -> sftp-server,
          '';
          # podman includes <tunables/global> only if /etc/apparmor.d/tunables/global exists;
          # without it containers-default fails to parse and the container won't start.
          # apparmor.d ships no global: this is the file the search path resolved to before.
          "tunables/global" = ''
            include "${pkgs.apparmor-profiles}/etc/apparmor.d/tunables/global"
          '';
        };
      };

      environment.systemPackages = [pkgs.apparmor-parser];

      # podman applies containers-default only when it finds apparmor_parser on PATH.
      systemd.services = lib.mkIf (config.virtualisation.oci-containers.backend == "podman") (
        lib.mapAttrs' (_: c: lib.nameValuePair c.serviceName {path = [pkgs.apparmor-parser];})
        config.virtualisation.oci-containers.containers
      );
    };
  };
}
