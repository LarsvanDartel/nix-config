# desktop.greetd.noctalia — the noctalia greeter on greetd, themed from stylix.
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

  # The session script calls cage, wlr-randr and dbus-run-session by name with no PATH.
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

  # The clock is bare text on the wallpaper; blurring and dimming toward `surface` keeps it
  # legible in either polarity.
  backdrop =
    pkgs.runCommand "noctalia-greeter-wallpaper.png" {nativeBuildInputs = [pkgs.imagemagick];}
    ''
      magick ${cfg.wallpaper} -blur 0x12 \
        -fill '${config.lib.stylix.colors.withHashtag.base00}' -colorize 65% $out
    '';
in {
  options.cosmos.profiles.desktop.addons.greetd.noctalia = {
    user = mkOption {
      type = str;
      default = "greeter";
      description = ''
        Account the greeter runs as. A graphical session with its own
        writable state, so it uses the dedicated system user greetd already
        creates rather than the primary user.
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
      description = "Background shown behind the login prompt, blurred and dimmed.";
    };
  };

  config = {
    cosmos.profiles.desktop.addons.greetd = {
      user = cfg.user;
      command = "${greeter}/bin/noctalia-greeter-session";
    };

    # The binary ignores XKB_*/XCURSOR_* env and reads only greeter.toml. Theme via `settings`, never
    # appearance.json: it is migrated once into mutable sync.toml and never re-read.
    services.displayManager.noctalia-greeter = {
      enable = true;
      package = greeter;

      cursorTheme = {
        inherit (cursor) name package;
      };

      settings = {
        # A qwerty greeter rejects a Dvorak-typed password.
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

        # `scheme = "Synced"` is what makes it render this palette. The
        # system's default mode: the greeter has no session to switch.
        appearance = {
          scheme = "Synced";
          theme_mode = config.stylix.polarity;
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
            path = "${backdrop}";
            fill_mode = "crop";
          };
        };
      };
    };

    environment.systemPackages = [greeter];

    # For noctalia-shell v5's "sync appearance" button.
    security.polkit.enable = true;

    cosmos.system.impermanence.persist.directories = [stateDir];

    systemd.tmpfiles.rules = [
      # One of two paths compiled into the greeter; the only one NixOS can own.
      "d /usr/share 0755 root root -"
      "L+ /usr/share/wayland-sessions - - - - ${sessionDir}"

      "d ${stateDir} 0755 ${cfg.user} ${cfg.user} -"
      "f ${stateDir}/greeter.log 0664 ${cfg.user} ${cfg.user} -"
      "f /var/log/noctalia-greeter.log 0664 ${cfg.user} ${cfg.user} -"
    ];

    # A Wayland greeter must not get a tty, or systemd hangs the unit.
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
