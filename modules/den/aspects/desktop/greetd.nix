# desktop.greetd (+ tuigreet). greetd is the login manager; tuigreet draws the
# session picker.
#
# Sessions are CURATED: each compositor aspect contributes exactly one entry via
# `cosmos.profiles.desktop.addons.greetd.sessions`, and tuigreet is pointed at a
# linkFarm of just those. Pointing it at the system-wide wayland-sessions dir
# instead lists Hyprland twice, because `programs.hyprland.withUWSM` installs
# BOTH `hyprland.desktop` ("Hyprland") and `hyprland-uwsm.desktop`
# ("Hyprland (uwsm-managed)") — that was the duplicate-sessions bug.
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

    # Only `default_session` — that is the greeter. `initial_session` is greetd's
    # *autologin* slot; pointing it at the same value registered the greeter twice.
    config.services.greetd = {
      enable = true;
      settings.default_session = {
        inherit (cfg) command user;
      };
    };
  };

  # The graphical alternative to tuigreet — same curated session list, noctalia's
  # look. The body lives in ./_greetd/noctalia.nix so voyager's
  # `specialisation.niri` can apply it too (specialisation bodies are plain
  # modules and cannot `include` a den aspect).
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

      # Exactly the entries the compositor aspects asked for — nothing else.
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

        # `--remember-user-session` persists the picked session per user, so the
        # choice sticks across logins (state lives in /var/cache/tuigreet).
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
