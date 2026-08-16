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
# Three things it hardcodes, and how they are satisfied here:
#
#   * Sessions come from /usr/share/wayland-sessions and
#     /usr/local/share/wayland-sessions only — no XDG_DATA_DIRS, no NixOS
#     session dir. A tmpfiles symlink points the first at the same curated
#     linkFarm tuigreet uses, so both greeters offer exactly the same entries.
#   * `noctalia-greeter-session` shells out to cage, wlr-randr and
#     dbus-run-session by name, and greetd's unit has no PATH to speak of, so
#     the package is re-wrapped with them.
#   * Theming comes from /var/lib/noctalia-greeter/appearance.json, normally
#     written by noctalia-shell v5's "sync to greeter" polkit action. Shell
#     4.7.7 has no such action, so the manifest is generated from the stylix
#     palette and symlinked in — no runtime sync, no admin prompt.
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

  # noctalia's own colour roles, mapped off the base16 scheme stylix is themed
  # with. The key names are the greeter's (snake_case), not the shell's.
  appearance = pkgs.writeText "noctalia-greeter-appearance.json" (builtins.toJSON {
    version = 1;
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
  });

  # Seeded, not managed: the greeter rewrites this file to remember the last
  # session and scheme, so it is copied in once and then left alone. `scheme`
  # must say "Synced" or the palette above is ignored in favour of a built-in.
  greeterConf = pkgs.writeText "noctalia-greeter.conf" (
    ''
      # noctalia-greeter greeter.conf
      greeter_user = ${cfg.user}
      scheme = Synced
    ''
    + lib.optionalString (cfg.defaultSession != null) ''
      default_session = ${cfg.defaultSession}
    ''
  );
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

    environment.systemPackages = [greeter];

    # The polkit action for noctalia-shell v5's "sync appearance" button. Unused
    # by shell 4.7.7 (which has no such button) but harmless, and it makes the
    # helper work by hand if you ever want to override the generated palette.
    security.polkit.enable = true;

    # The greeter remembers the last session and colour scheme in greeter.conf;
    # without this it forgets them on every boot.
    cosmos.system.impermanence.persist.directories = [stateDir];

    systemd.tmpfiles.rules = [
      # /usr/share/wayland-sessions is one of the two paths compiled into the
      # greeter, and the only one NixOS can plausibly own. It does not exist
      # here, so it is created as a link to the curated list.
      "d /usr/share 0755 root root -"
      "L+ /usr/share/wayland-sessions - - - - ${sessionDir}"

      "d ${stateDir} 0755 ${cfg.user} ${cfg.user} -"
      "L+ ${stateDir}/appearance.json - - - - ${appearance}"
      "C ${stateDir}/greeter.conf 0644 ${cfg.user} ${cfg.user} - ${greeterConf}"
      "f ${stateDir}/greeter.log 0664 ${cfg.user} ${cfg.user} -"
      "f /var/log/noctalia-greeter.log 0664 ${cfg.user} ${cfg.user} -"
    ];

    # Keyboard layout and cursor for the greeter, neither of which it inherits.
    #
    # Both are the same class of bug: this greeter is a Wayland client in its
    # own cage compositor, running as the unprivileged `greeter` account, and a
    # systemd unit's environment is nearly empty — greetd's was LOCALE_ARCHIVE,
    # PATH and TZDIR and nothing else.
    #
    #   * xkb. `services.xserver.xkb` configures X11 and the console (via
    #     console.useXkbConfig), and cage reads neither: libxkbcommon takes its
    #     defaults from XKB_DEFAULT_*. Without these the login prompt is plain
    #     us qwerty while the layout here is Programmer Dvorak, so a password
    #     typed correctly is rejected — which looks like a wrong password
    #     rather than a wrong layout, and is why this is worth fixing properly
    #     rather than living with.
    #   * cursor. The theme is set through home-manager (stylix →
    #     home.pointerCursor), and home-manager configures the *primary user*.
    #     The greeter is a different account with no home, so it fell back to
    #     the default X cursor. Read from the primary user's stylix settings —
    #     the same trick `wallpaper` above uses, and for the same reason.
    #
    # XCURSOR_PATH has to be explicit: the theme is a store path, and nothing
    # puts it on the default icon search path for a system service.
    systemd.services.greetd.environment = let
      xkb = config.services.xserver.xkb;
      cursor = config.home-manager.users.${config.cosmos.user.name}.stylix.cursor or null;
    in
      {
        XKB_DEFAULT_LAYOUT = xkb.layout;
        XKB_DEFAULT_MODEL = xkb.model;
        XKB_DEFAULT_VARIANT = xkb.variant;
        XKB_DEFAULT_OPTIONS = xkb.options;
      }
      // lib.optionalAttrs (cursor != null) {
        XCURSOR_THEME = cursor.name;
        XCURSOR_SIZE = toString cursor.size;
        XCURSOR_PATH = "${cursor.package}/share/icons";
      };

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
