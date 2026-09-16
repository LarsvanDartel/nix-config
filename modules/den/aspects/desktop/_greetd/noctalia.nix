# The noctalia greeter, as a plain NixOS module *factory*: imported by BOTH
# `den.aspects.desktop.greetd.noctalia` (see ../greetd.nix) and voyager's
# `specialisation.niri` (specialisation bodies cannot `include` a den aspect).
# Call as `import ./_greetd/noctalia.nix {}`.
#
# noctalia-greeter is a standalone C++ Wayland client (not part of the shell)
# rendering greetd's prompt in noctalia's look, run inside cage via the
# `noctalia-greeter-session` wrapper. Two things it hardcodes:
#   * sessions come only from /usr/share/wayland-sessions (no XDG_DATA_DIRS) —
#     a tmpfiles symlink points it at the same curated linkFarm tuigreet uses;
#   * the session wrapper shells out to cage, wlr-randr and dbus-run-session
#     by name, and greetd's unit has no PATH — so the package is re-wrapped.
#
# Theming goes through `settings`, which the upstream module force-symlinks
# into /var/lib/noctalia-greeter/greeter.toml (re-read on every launch). Do NOT
# be tempted back to writing appearance.json by hand: since 1.3.0 it is only
# *migrated once* into the mutable sync.toml ("UI + Sync; not managed by Nix")
# and never read again — a `C+` tmpfiles rule force-refreshing it every deploy
# still leaves the greeter silently rendering whatever got baked into sync.toml
# on day one (exactly how the background went black: sync.toml pinned the first
# wallpaper store path, later garbage-collected).
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

  # The primary user's cursor, for the same reason `wallpaper` below reads from
  # home-manager: the greeter account has no home and therefore no stylix.
  cursor = config.home-manager.users.${config.cosmos.user.name}.stylix.cursor;

  # cage/wlr-randr/dbus are looked up on PATH by the session wrapper.
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
      # The primary user's stylix image: only the home side sets it, and it is
      # a store path the unprivileged greeter account can read (~/Pictures
      # could not be).
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

    # Keyboard and cursor, through nixpkgs' own module. An earlier attempt set
    # XKB_DEFAULT_*/XCURSOR_* on the greetd unit and was silently inert —
    # neither string is anywhere in the 1.2.1 binary; it reads only its own
    # greeter.toml. That matters most for layout: this machine is Programmer
    # Dvorak, and a greeter defaulting to qwerty rejects a correctly typed
    # password as though it were wrong. `settings` is symlinked to greeter.toml
    # as a store path (tmpfiles `L+`) — nothing to go stale, and no `C` vs
    # `C+` trap. `package` is the wrapped build: the upstream module does not
    # wrap cage/dbus-run-session.
    services.displayManager.noctalia-greeter = {
      enable = true;
      package = greeter;

      # Fills in settings.cursor.theme and .path for us.
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

        # Without this the greeter refuses to start the PAM conversation on an
        # empty password field, so pam_u2f's touch prompt (auth sufficient,
        # first in the stack — see core.yubikey) never fires.
        auth.allow_empty_password = true;

        # The greeter's own (snake_case) colour roles off the base16 scheme;
        # `scheme = "Synced"` is what makes it render this table instead of a
        # built-in preset.
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

    # The polkit action for noctalia-shell v5's "sync appearance" button. Unused
    # by shell 4.7.7 (which has no such button) but harmless, and it makes the
    # helper work by hand if you ever want to override the generated palette.
    security.polkit.enable = true;

    # greeter.toml above is Nix-managed and rewritten every activation, but
    # sync.toml (last-used session, output layout) is the greeter's own
    # mutable state and must survive reboots.
    cosmos.system.impermanence.persist.directories = [stateDir];

    systemd.tmpfiles.rules = [
      # /usr/share/wayland-sessions is one of the two paths compiled into the
      # greeter, and the only one NixOS can plausibly own. It does not exist
      # here, so it is created as a link to the curated list.
      "d /usr/share 0755 root root -"
      "L+ /usr/share/wayland-sessions - - - - ${sessionDir}"

      "d ${stateDir} 0755 ${cfg.user} ${cfg.user} -"
      "f ${stateDir}/greeter.log 0664 ${cfg.user} ${cfg.user} -"
      "f /var/log/noctalia-greeter.log 0664 ${cfg.user} ${cfg.user} -"
    ];

    # The tuigreet aspect hands greetd a tty for its TUI; a Wayland greeter must
    # not have one, or systemd hangs the unit on a terminal nobody reads.
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
