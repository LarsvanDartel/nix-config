# desktop.greetd (+ tuigreet). Sessions are CURATED: each compositor aspect
# contributes one entry and the greeter gets a linkFarm of just those — the
# system-wide wayland-sessions dir lists Hyprland twice under withUWSM.
{den, ...}: {
  den.aspects.desktop.greetd.nixos = {
    config,
    lib,
    ...
  }: let
    inherit (lib.types) str listOf submodule path;
    inherit (lib.options) mkOption;

    cfg = config.cosmos.profiles.desktop.addons.greetd;
  in {
    options.cosmos.profiles.desktop.addons.greetd = {
      command = mkOption {
        type = str;
        default = "";
        description = "Command to run to show greeter";
      };

      user = mkOption {
        type = str;
        default = config.cosmos.user.name;
        defaultText = "the primary user";
        description = ''
          Account the greeter itself runs as. tuigreet uses the primary user so
          its remembered-session cache is per-user; graphical greeters override
          this with the dedicated `greeter` system account.
        '';
      };

      sessions = mkOption {
        default = [];
        description = ''
          Wayland sessions offered by the greeter. Compositor aspects each
          contribute one entry, so the picker never shows duplicates.
        '';
        type = listOf (submodule {
          options = {
            name = mkOption {
              type = str;
              description = ''File name of the entry, e.g. "niri.desktop".'';
            };
            path = mkOption {
              type = path;
              description = "The .desktop file to offer.";
            };
          };
        });
      };
    };

    config = {
      # Not `initial_session`: that is greetd's autologin slot; setting it to
      # the same value registered the greeter twice.
      services.greetd = {
        enable = true;
        settings.default_session = {
          inherit (cfg) command user;
        };
      };

      # greetd's PAM stack substacks `login`, so enableGnomeKeyring on
      # `greetd` itself is a no-op; without this the keyring starts locked
      # every boot and all secrets look wiped.
      security.pam.services.login.enableGnomeKeyring = true;

      # System-level gnome-keyring is what registers gcr's prompter D-Bus
      # services; without it keyring unlock dialogs silently never appear.
      services.gnome.gnome-keyring.enable = true;
      # Defaults on with gnome-keyring and collides with core.ssh's
      # `programs.ssh.startAgent` (only one SSH agent may be installed).
      services.gnome.gcr-ssh-agent.enable = false;
    };
  };

  # Body in ./_greetd/noctalia.nix, shared with voyager's specialisation.
  den.aspects.desktop.greetd.noctalia = {
    includes = [den.aspects.desktop.greetd];
    nixos = import ./_greetd/noctalia.nix {};
  };

  den.aspects.desktop.greetd.tuigreet = {
    includes = [den.aspects.desktop.greetd];
    nixos = {
      config,
      lib,
      pkgs,
      ...
    }: let
      inherit (lib.types) str;
      inherit (lib.options) mkOption;
      inherit (lib.modules) mkDefault;
      inherit (lib.strings) concatStringsSep;
      inherit (lib.lists) optional;

      greetd = config.cosmos.profiles.desktop.addons.greetd;
      cfg = greetd.tuigreet;

      tuigreet = "${pkgs.tuigreet}/bin/tuigreet";

      sessionDir = pkgs.linkFarm "greetd-wayland-sessions" greetd.sessions;
    in {
      options.cosmos.profiles.desktop.addons.greetd.tuigreet = {
        greeting = mkOption {
          type = str;
          default = "Welcome to ${config.networking.hostName}";
          description = "Greeting message to show";
        };
        command = mkOption {
          type = str;
          default = "";
          description = ''
            Fallback session command, used only when no `sessions` are
            contributed (otherwise the picker drives the choice).
          '';
        };
      };

      config = {
        cosmos.system.impermanence.persist.directories = ["/var/cache/tuigreet"];

        cosmos.profiles.desktop.addons.greetd.command = mkDefault (
          concatStringsSep " " (
            [
              tuigreet
              "--remember"
              "--remember-user-session"
              ''--greeting "${cfg.greeting}"''
              "--time"
              "--asterisks"
            ]
            ++ optional (greetd.sessions != []) "--sessions ${sessionDir}"
            ++ optional (cfg.command != "") ''--cmd "${cfg.command}"''
          )
        );

        systemd.services.greetd.serviceConfig = {
          Type = "idle";
          StandardInput = "tty";
          StandardOutput = "tty";
          StandardError = "journal";
          TTYReset = true;
          TTYVHangup = true;
          TTYVTDisallocate = true;
        };
      };
    };
  };
}
