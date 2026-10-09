# The noctalia greeter, as a plain NixOS module factory shared by
# `den.aspects.desktop.greetd.noctalia` and voyager's `specialisation.niri`.
#
# It hardcodes /usr/share/wayland-sessions (hence the tmpfiles symlink) and
# calls cage/wlr-randr/dbus-run-session by name with no PATH (hence the
# re-wrap). Do NOT go back to writing appearance.json: since 1.3.0 it is only
# migrated once into mutable sync.toml and never re-read (that is how the
# background went black); theme via `settings`/greeter.toml.
{}: {
  config,
  lib,
  pkgs,
  ...
}: let
  inherit (lib.options) mkOption;
  inherit (lib.types) nullOr path str;
  inherit (lib.modules) mkForce;

  greetd = config.cosmos.profiles.desktop.addons.greetd;
  cfg = greetd.noctalia;

  stateDir = "/var/lib/noctalia-greeter";

  # The greeter account has no home and therefore no stylix.
  cursor = config.home-manager.users.${config.cosmos.user.name}.stylix.cursor;

  greeter = pkgs.symlinkJoin {
    name = "noctalia-greeter-wrapped";
    paths = [pkgs.noctalia-greeter];
    nativeBuildInputs = [pkgs.makeWrapper];
    postBuild = ''
      wrapProgram $out/bin/noctalia-greeter-session \
        --prefix PATH : ${lib.makeBinPath [pkgs.cage pkgs.wlr-randr pkgs.dbus]}
    '';
  };

  sessionDir = pkgs.linkFarm "greetd-wayland-sessions" greetd.sessions;
in {
  options.cosmos.profiles.desktop.addons.greetd.noctalia = {
    user = mkOption {
      type = str;
      default = "greeter";
      description = ''
        Account the greeter runs as. Unlike tuigreet this is a graphical
        session with its own writable state, so it uses the dedicated system
        user greetd already creates rather than the primary user.
      '';
    };

    defaultSession = mkOption {
      type = nullOr str;
      default = null;
      example = "niri";
      description = ''
        Session preselected when the greeter opens, matched against the
        `Name=` of a contributed .desktop entry. Overrides the last-used
        session; null leaves the choice to whatever was picked last.
      '';
    };

    wallpaper = mkOption {
      type = nullOr path;
      # A store path the unprivileged greeter can read (~/Pictures is not).
      default = config.home-manager.users.${config.cosmos.user.name}.stylix.image or null;
      defaultText = "the primary user's stylix.image";
      description = "Background shown behind the login prompt.";
    };
  };

  config = {
    cosmos.profiles.desktop.addons.greetd = {
      user = cfg.user;
      command = "${greeter}/bin/noctalia-greeter-session";
    };

    # XKB_DEFAULT_*/XCURSOR_* env is ignored by the binary; it reads only
    # greeter.toml. Layout matters: a qwerty greeter rejects a Dvorak-typed
    # password. `package` is the wrapped build.
    services.displayManager.noctalia-greeter = {
      enable = true;
      package = greeter;

      cursorTheme = {
        inherit (cursor) name package;
      };

      settings = {
        keyboard = {
          inherit (config.services.xserver.xkb) layout variant options;
        };
        cursor.size = cursor.size;

        session = lib.optionalAttrs (cfg.defaultSession != null) {
          default = cfg.defaultSession;
        };

        # Else pam_u2f's touch prompt (see core.yubikey) never fires on an
        # empty password field.
        auth.allow_empty_password = true;

        # `scheme = "Synced"` is what makes it render this palette.
        appearance = {
          scheme = "Synced";
          theme_mode = "dark";
          palette = with config.lib.stylix.colors.withHashtag; {
            primary = base07;
            on_primary = base00;
            secondary = base0C;
            on_secondary = base00;
            tertiary = base0F;
            on_tertiary = base00;
            error = base08;
            on_error = base00;
            surface = base00;
            on_surface = base06;
            surface_variant = base01;
            on_surface_variant = base04;
            outline = base03;
            shadow = base00;
            hover = base0F;
            on_hover = base00;
          };
          wallpaper = lib.optionalAttrs (cfg.wallpaper != null) {
            path = "${cfg.wallpaper}";
            fill_mode = "crop";
          };
        };
      };
    };

    environment.systemPackages = [greeter];

    # For noctalia-shell v5's "sync appearance" button.
    security.polkit.enable = true;

    # sync.toml (last session, output layout) is the greeter's mutable state.
    cosmos.system.impermanence.persist.directories = [stateDir];

    systemd.tmpfiles.rules = [
      # One of two paths compiled into the greeter; the only one NixOS can own.
      "d /usr/share 0755 root root -"
      "L+ /usr/share/wayland-sessions - - - - ${sessionDir}"

      "d ${stateDir} 0755 ${cfg.user} ${cfg.user} -"
      "f ${stateDir}/greeter.log 0664 ${cfg.user} ${cfg.user} -"
      "f /var/log/noctalia-greeter.log 0664 ${cfg.user} ${cfg.user} -"
    ];

    # A Wayland greeter must not get tuigreet's tty, or systemd hangs the unit.
    systemd.services.greetd.serviceConfig = {
      StandardInput = mkForce "null";
      StandardOutput = mkForce "journal";
      StandardError = mkForce "journal";
      TTYReset = mkForce false;
      TTYVHangup = mkForce false;
      TTYVTDisallocate = mkForce false;
    };
  };
}
