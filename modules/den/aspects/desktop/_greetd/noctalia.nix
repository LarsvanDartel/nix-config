# The noctalia greeter, as a plain NixOS module *factory*.
#
# Imported by BOTH `den.aspects.desktop.greetd.noctalia` (see ../greetd.nix) and
# voyager's `specialisation.niri` — specialisation bodies are ordinary NixOS
# modules and cannot `include` a den aspect, so the shared content lives here.
# Call it as `import ./_greetd/noctalia.nix {}`.
#
# noctalia-greeter is a standalone C++ Wayland client (not part of the shell)
# that renders greetd's login prompt in noctalia's visual language. It runs
# inside cage, started by the `noctalia-greeter-session` wrapper.
#
# Two things it hardcodes, and how they are satisfied here:
#
#   * Sessions come from /usr/share/wayland-sessions and
#     /usr/local/share/wayland-sessions only — no XDG_DATA_DIRS, no NixOS
#     session dir. A tmpfiles symlink points the first at the same curated
#     linkFarm tuigreet uses, so both greeters offer exactly the same entries.
#   * `noctalia-greeter-session` shells out to cage, wlr-randr and
#     dbus-run-session by name, and greetd's unit has no PATH to speak of, so
#     the package is re-wrapped with them.
#
# Theming (palette, wallpaper, default session) goes through
# `services.displayManager.noctalia-greeter.settings`, which the upstream
# NixOS module force-symlinks into /var/lib/noctalia-greeter/greeter.toml on
# every activation — the ONE file the greeter documents as "declarative;
# Nix-safe; UI and Sync never write this". Do not be tempted back to writing
# /var/lib/noctalia-greeter/appearance.json by hand: pre-1.3.0 that file was
# read on every launch, but 1.3.0 added a separate, mutable
# /var/lib/noctalia-greeter/sync.toml ("UI + Sync; not managed by Nix") and
# only *migrates* legacy appearance.json into it once, the first time sync.toml
# doesn't exist yet. After that one migration the greeter never looks at
# appearance.json again — a `C+` tmpfiles rule can force-refresh it every
# deploy and the greeter will keep rendering whatever palette/wallpaper got
# baked into sync.toml on day one, silently, forever (this is exactly how the
# background went black: the themed wallpaper is a content-addressed store
# path that changes on every stylix/wallpaper rebuild, sync.toml pinned the
# very first one, and that generation was eventually garbage-collected out
# from under it). greeter.toml doesn't have this problem — it is re-read by
# the greeter on every launch, not migrated-and-forgotten.
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
      # The primary user's themed stylix background. Read from home-manager
      # because only the home side sets `stylix.image`; it is a store path, so
      # the unprivileged greeter account can read it — a file under ~/Pictures
      # could not.
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

    # Keyboard and cursor, through nixpkgs' own module rather than by hand.
    #
    # These are the two things the greeter will NOT pick up from anywhere else.
    # An earlier attempt set XKB_DEFAULT_* and XCURSOR_* on the greetd unit and
    # was silently inert: `strings` on noctalia-greeter 1.2.1 finds neither
    # variable anywhere in the binary. It reads its own greeter.toml and
    # nothing else.
    #
    # That matters most for the layout. This machine is Programmer Dvorak and
    # the greeter defaulted to us qwerty, so a correctly typed password came
    # back rejected — indistinguishable from a wrong password unless you
    # already suspect the layout.
    #
    # `settings` is written to greeter.toml as a *store symlink* (tmpfiles
    # `L+`), which is why this is worth using over hand-writing the file: no
    # copy to go stale, and no repeat of the `C` vs `C+` trap below.
    #
    # `package` is the wrapped build, not pkgs.noctalia-greeter: 1.2.1's
    # session script still calls dbus-run-session and cage by name, and the
    # upstream module does not wrap them.
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

        # noctalia's own colour roles, mapped off the base16 scheme stylix is
        # themed with. The key names are the greeter's (snake_case), not the
        # shell's. `scheme = "Synced"` is what makes the greeter render this
        # table instead of a built-in preset.
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
