# The noctalia home config, as a plain home-manager module *factory*.
#
# Imported by BOTH `den.aspects.home.noctalia` (see ../noctalia.nix) and
# voyager's `specialisation.niri` — specialisation bodies are ordinary NixOS
# modules and cannot `include` a den aspect, so the shared content lives here.
# Call it as `import ./_noctalia/home.nix {inherit inputs;}`.
{inputs}: {
  config,
  lib,
  pkgs,
  ...
}: let
  inherit (lib.options) mkOption mkEnableOption;
  inherit (lib.types) enum bool;

  cfg = config.cosmos.desktops.noctalia;
  fonts = config.cosmos.desktops.common.styling.fonts;

  # Set once in _styling/default.nix. stylix's own noctalia-shell target would
  # apply these, but it is gated on `options.programs ? noctalia-shell` and this
  # noctalia is a wrapped package rather than that home-manager module, so the
  # target never fires and the values are threaded through by hand — same as the
  # colours and fonts above and below.
  opacity = config.stylix.opacity;
  wallpapers = config.cosmos.desktops.wallpapers;

  widget = id: {inherit id;};

  # Plugin widgets are addressed as `plugin:<id>` (BarWidgetLoader splits on the
  # prefix to look the component up in the plugin registry rather than
  # Modules/Bar/Widgets). Placement has to live here: bar.widgets is part of the
  # store-owned settings.json, so it cannot be changed from the settings panel.
  pluginWidget = id: {id = "plugin:${id}";};

  # Widgets that can show their value permanently or only on hover. "alwaysShow"
  # keeps the reading (volume %, brightness %, SSID, …) visible at all times.
  valueWidget = id: {
    inherit id;
    displayMode = "alwaysShow";
  };

  noctalia = inputs.nix-wrapper-modules.wrappers.noctalia-shell.wrap {
    inherit pkgs;

    # No `outOfStoreConfig`: supplying only `settings` makes the wrapper point
    # NOCTALIA_SETTINGS_FILE straight at the generated store file, so nix is
    # authoritative and every rebuild applies immediately.
    #
    # Trade-off: noctalia's settings panel can no longer save — settings are
    # changed here, not in the GUI. Everything else it owns (colors.json,
    # colorschemes/, plugins/) still lives in ~/.config/noctalia and stays
    # writable, so plugin installs and runtime state keep working.

    settings = {
      bar = {
        barType = "simple";
        inherit (cfg.bar) position density;

        # flat + edge-to-edge: no capsule pills, no rounding, no margins.
        # Still flat, but no longer opaque — see `enableBlurBehind` below.
        showCapsule = false;
        showOutline = false;
        backgroundOpacity = opacity.desktop;
        marginVertical = 0;
        marginHorizontal = 0;
        frameRadius = 0;
        frameThickness = 0;
        outerCorners = false;
        widgetSpacing = 8;
        contentPadding = 2;
        displayMode = "always_visible";
        enableExclusionZoneInset = true;
        rightClickAction = "controlCenter";

        # Three sides, and until recently fourteen widgets were on one of them
        # while the left held two. Split by what a thing tells you about rather
        # than by what kind of thing it is:
        #
        #   left    what you are looking at — workspace, window, what it is
        #           playing, whether it is watching you
        #   center  the clock, alone, because it is the one thing that has to
        #           sit still
        #   right   the machine's own state, and the ways into it
        widgets = {
          left =
            map widget ["Workspace" "ActiveWindow"]
            ++ [
              # The widest widget on the bar by a distance: it carries a track
              # title. It belongs next to the window it is playing from, and
              # moving it here is most of what bought the room.
              (widget "MediaMini")
              # Only draws itself while the mic, camera or a screencast is
              # actually live, so it costs nothing at rest.
              (pluginWidget "privacy-indicator")
            ];
          center = map widget ["Clock"];
          right =
            # Percentages are two or three characters and worth having at a
            # glance, so they stay on screen.
            map valueWidget ["Volume" "Brightness"]
            # An SSID and a paired device name are not: both run to twenty-odd
            # characters for something that changes a few times a week. Icon
            # here, reading on hover.
            ++ map widget ["Network" "Bluetooth"]
            ++ [
              # Replaces kdeconnect-indicator's tray icon, which plugins.nix
              # turns off.
              (pluginWidget "kde-connect")
              # Auto-hides when disconnected.
              (pluginWidget "protonvpn")
              (pluginWidget "netbird")
              (pluginWidget "thinkpad-fan")
            ]
            # `icon-always` keeps the pill open, so the charge percentage shows
            # permanently. `hideIfNotDetected` is what makes the widget vanish
            # entirely when UPower reports no battery — see desktop.power, which
            # is what actually makes the battery detectable.
            ++ [
              {
                id = "Battery";
                displayMode = "icon-always";
                hideIfNotDetected = false;
              }
            ]
            ++ [
              {
                id = "Tray";
                # blueman-applet duplicates the Bluetooth widget three slots to
                # the left. Two rules because noctalia matches on the tooltip
                # title when there is one and falls back to the item id: the
                # tooltip is state-dependent ("Bluetooth Disabled", "Bluetooth
                # Enabled", …), the id is always "blueman". Globs, anchored,
                # case-insensitive. The applet keeps running — it is also the
                # pairing agent.
                blacklist = ["blueman" "Bluetooth*"];
              }
            ]
            ++ map widget ["NotificationHistory" "ControlCenter"];
          # Night light, keep-awake and the wallpaper picker stay *enabled* —
          # they just live in the control centre rather than on the bar.
          #
          # So do several installed plugins, deliberately kept off the bar:
          # screen-toolkit is a control-centre shortcut (below); ssh-sessions
          # and niri-workspaces are launcher providers (type `>ws`);
          # keybind-cheatsheet, display-settings and plugin-manager are on
          # keybinds (see _niri/system.nix). battery-monitor-plus and
          # model-usage have bar widgets but no default slot — add
          # `plugin:battery-monitor-plus` / `plugin:model-usage` here to
          # surface them.
        };
      };

      # FIVE PER SIDE, no more. ShortcutsCard is a fixed-height row of
      # non-shrinking items in a half-width box with no wrapping, so a sixth
      # entry renders outside the card's rounded background rather than being
      # laid out.
      #
      # A plugin can only go here if its manifest declares a
      # `controlCenterWidget` entry point — of the installed set that is
      # kde-connect, plugin-manager and screen-toolkit, and nothing else.
      # battery-threshold has only `barWidget`, so it lives on a keybind
      # (see _niri/system.nix); putting it here renders nothing.
      controlCenter.shortcuts = {
        left =
          map widget ["Network" "Bluetooth" "WallpaperSelector" "NoctaliaPerformance"]
          ++ [(pluginWidget "screen-toolkit")];
        right =
          # Notifications (the do-not-disturb toggle) gave up its slot: the
          # kde-connect bar widget only draws itself when a device is actually
          # reachable, and its control-centre widget has no such condition, so
          # this is the only way to reach it with the phone off the network.
          # DND is still on `notifications toggleDND` over IPC.
          map widget ["PowerProfile" "KeepAwake" "NightLight"]
          ++ [
            (pluginWidget "kde-connect")
            (pluginWidget "plugin-manager")
          ];
      };

      # The bar covers everything the dock would, and a second always-present
      # surface on a laptop panel is just lost pixels.
      dock.enabled = false;

      # Built-in Nord scheme — the same base16 palette stylix themes the rest with.
      colorSchemes = {
        predefinedScheme = "Nord";
        darkMode = true;
        useWallpaperColors = false;
      };

      # Minimal chrome: flat, no shadows, no faux screen corners.
      #
      # Blur is the exception, and it is what makes the translucency above
      # legible rather than noisy. noctalia asks for it through the
      # `ext-background-effect` protocol (Quickshell's BackgroundEffect), which
      # means the compositor blurs exactly the shape noctalia asked for —
      # corner radii included — instead of us approximating it with a rule.
      # niri 26.04 implements that protocol, so nothing else is needed on the
      # niri side for the bar, the panels and the launcher.
      #
      # It reaches only those three surfaces though: notifications, OSDs and
      # toasts are separate windows with no BackgroundEffect attached, so they
      # are blurred by a niri layer-rule instead (see _niri/system.nix). Under
      # Hyprland the equivalent is already in _hyprland/rules.nix.
      general = {
        enableShadows = false;
        enableBlurBehind = true;
        showScreenCorners = false;
        showChangelogOnStartup = false;

        # Lock screen.
        #
        # `autoStartAuth` begins the PAM conversation as soon as the lock screen
        # appears, which is what starts the fprintd scan without a keypress, and
        # `allowPasswordWithFprintd` keeps the password field live while the
        # reader waits — without it a failed/absent finger locks you out of
        # typing. `enableLockScreenCountdown` is the auto-dismiss timer on the
        # session buttons; off, so nothing happens unless you pick it.
        autoStartAuth = true;
        allowPasswordWithFprintd = true;
        enableLockScreenMediaControls = true;
        enableLockScreenCountdown = false;
        showSessionButtonsOnLockScreen = true;
        showHibernateOnLockScreen = true;
        lockScreenAnimations = false;
        lockOnSuspend = true;
      };

      ui = {
        # The interface font, not stylix's sansSerif: Cozette is what the rest of
        # the desktop (bar, popups, terminal) is set in, and mixing it with
        # DejaVu across the same screen is what made the shell look off.
        fontDefault = fonts.interface.name;
        fontFixed = fonts.monospace.name;
        panelBackgroundOpacity = opacity.desktop;
        # The panel *background* is translucent; the widgets drawn on it are
        # not. Stacking two levels of transparency is what turns frosted glass
        # into an unreadable smear.
        translucentWidgets = false;
      };

      # Deliberately spare: a single-column list with no category headers, no
      # icon plates and tight rows — the closest noctalia gets to a bare
      # type-and-enter launcher. The search providers (settings, windows,
      # sessions, clipboard) cost nothing visually and stay on.
      appLauncher = {
        enableClipboardHistory = cfg.widgets.clipboardHistory;
        terminalCommand = "${config.cosmos.cli.terminals.defaultStandalone} -e";
        viewMode = "list";
        density = "compact";
        position = "center";
        showCategories = false;
        showIconBackground = false;
        sortByMostUsed = true;
      };

      # No countdown — the menu waits for a choice instead of acting on its own.
      # Keybinds are mnemonic rather than positional, so they read off the menu.
      sessionMenu = {
        enableCountdown = false;
        showKeybinds = true;
        showHeader = false;
        position = "center";
        powerOptions = [
          {
            action = "lock";
            enabled = true;
            keybind = "L";
          }
          {
            action = "suspend";
            enabled = true;
            keybind = "S";
          }
          {
            action = "hibernate";
            enabled = true;
            keybind = "H";
          }
          {
            action = "reboot";
            enabled = true;
            keybind = "R";
          }
          {
            action = "logout";
            enabled = true;
            keybind = "E";
          }
          {
            action = "shutdown";
            enabled = true;
            keybind = "P";
          }
          {
            action = "rebootToUefi";
            enabled = true;
            keybind = "U";
          }
        ];
      };

      # DDC/CI, so the brightness widget also drives an external monitor.
      brightness.enableDdcSupport = cfg.widgets.externalBrightness;

      nightLight = {
        enabled = cfg.widgets.nightLight;
        autoSchedule = true;
      };

      idle.enabled = cfg.widgets.idleInhibitor;

      notifications = {
        enabled = cfg.notifications.enable;
        backgroundOpacity = opacity.popups;
      };

      # Volume/brightness popups, same treatment as notifications.
      osd.backgroundOpacity = opacity.popups;

      # Backgrounds the wallpaper picker browses (see home.wallpapers).
      wallpaper.directory = wallpapers.directory;

      # Drives the weather widget and the night light's sunrise/sunset schedule.
      # Pinned rather than geolocated, so it works offline and doesn't phone out.
      location = {
        name = "Eindhoven";
        autoLocate = false;
      };
    };
  };

  # The wallpaper choice is runtime state, not a setting: noctalia keeps it in
  # its cache, and `defaultWallpaper` is the fallback used for any screen that
  # has no pick yet. Seeding the cache is therefore how a *default* wallpaper is
  # expressed — writing it into settings.json would do nothing.
  wallpaperCache = builtins.toJSON {
    wallpapers = {};
    usedRandomWallpapers = {};
    defaultWallpaper = wallpapers.defaultWallpaper;
  };
in {
  imports = [(import ./plugins.nix {})];

  options.cosmos.desktops.noctalia = {
    bar = {
      enable = mkEnableOption "the noctalia bar" // {default = true;};
      position = mkOption {
        type = enum ["top" "bottom" "left" "right"];
        default = "top";
        description = "Screen edge the bar is docked to.";
      };
      density = mkOption {
        type = enum ["compact" "default" "comfortable"];
        default = "compact";
        description = "Bar height / padding.";
      };
    };

    launcher.enable = mkEnableOption "noctalia's application launcher" // {default = true;};
    notifications.enable = mkEnableOption "noctalia's notification daemon" // {default = true;};
    lock.enable = mkEnableOption "noctalia's lock screen" // {default = true;};

    widgets = {
      clipboardHistory = mkOption {
        type = bool;
        default = true;
        description = "Clipboard history in the launcher (via cliphist).";
      };
      nightLight = mkOption {
        type = bool;
        default = true;
        description = "Scheduled colour-temperature shift (via wlsunset).";
      };
      externalBrightness = mkOption {
        type = bool;
        default = true;
        description = "DDC/CI control of external monitor brightness (via ddcutil).";
      };
      idleInhibitor = mkOption {
        type = bool;
        default = true;
        description = "Idle/suspend management and the keep-awake toggle.";
      };
    };
  };

  config = {
    home.packages =
      [noctalia]
      ++ lib.optional cfg.widgets.clipboardHistory pkgs.cliphist;

    cosmos.system.impermanence.persist.directories = [
      ".config/noctalia"
      # Nominally a cache, actually where the picked wallpaper, per-screen, is
      # remembered. Losing it on every boot would reset the background.
      ".cache/noctalia"
    ];

    # Seeded, not managed: written once so a fresh machine comes up with a
    # background, then left alone for the picker to overwrite.
    home.activation.noctaliaDefaultWallpaper = lib.hm.dag.entryAfter ["writeBoundary"] ''
      _cache=${lib.escapeShellArg "${config.xdg.cacheHome}/noctalia"}
      if [ ! -e "$_cache/wallpapers.json" ]; then
        run mkdir -p "$_cache"
        run cp ${pkgs.writeText "noctalia-wallpapers.json" wallpaperCache} "$_cache/wallpapers.json"
        run chmod u+w "$_cache/wallpapers.json"
      fi
    '';

    # Compositor-agnostic autostart: both niri and Hyprland/UWSM reach this target.
    systemd.user.services.noctalia = {
      Unit = {
        Description = "noctalia shell";
        PartOf = ["graphical-session.target"];
        After = ["graphical-session.target"];
      };
      Service = {
        ExecStart = lib.getExe noctalia;
        # Without this the lock screen probes /etc/pam.d at startup to guess a
        # stack. `login` is what it would land on anyway, and on NixOS that is
        # the stack `services.fprintd` wires pam_fprintd into — naming it
        # outright makes the fingerprint path deterministic.
        Environment = ["NOCTALIA_PAM_SERVICE=login"];
        Restart = "on-failure";
        RestartSec = 2;
        Slice = "session.slice";
      };
      Install.WantedBy = ["graphical-session.target"];
    };
  };
}
