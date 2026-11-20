# desktop.greetd — greetd login offering only the sessions compositor aspects contribute.
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
          Account the greeter itself runs as. Graphical greeters override this
          with the dedicated `greeter` system account.
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
      # Not `initial_session`: that is greetd's autologin slot and registers the greeter twice.
      services.greetd = {
        enable = true;
        settings.default_session = {
          inherit (cfg) command user;
        };
      };

      # greetd's PAM stack substacks `login`; the keyring on `greetd` itself is a no-op and
      # starts locked every boot.
      security.pam.services.login.enableGnomeKeyring = true;

      # System-level gnome-keyring is what registers gcr's prompter D-Bus
      # services; without it keyring unlock dialogs silently never appear.
      services.gnome.gnome-keyring.enable = true;
      # Defaults on with gnome-keyring and collides with core.ssh's
      # `programs.ssh.startAgent` (only one SSH agent may be installed).
      services.gnome.gcr-ssh-agent.enable = false;

      # Stop the user manager when the last session ends: a quick re-login otherwise reuses the old
      # manager, whose compositor and noctalia units still target the dead session.
      services.logind.settings.Login.UserStopDelaySec = 0;
    };
  };

  den.aspects.desktop.greetd.noctalia = {
    includes = [den.aspects.desktop.greetd];
    nixos = import ./_greetd/noctalia.nix {};
  };
}
