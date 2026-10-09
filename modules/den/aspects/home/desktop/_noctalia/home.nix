# The noctalia home config, as a plain home-manager module factory: also imported
# by voyager's `specialisation.niri`, which cannot `include` a den aspect.
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

  # stylix's noctalia-shell target never fires (gated on `options.programs ?
  # noctalia-shell`; this is a wrapped package), so values are threaded by hand.
  opacity = config.stylix.opacity;
  wallpapers = config.cosmos.desktops.wallpapers;

  widget = id: {inherit id;};

  pluginWidget = id: {id = "plugin:${id}";};

  valueWidget = id: {
    inherit id;
    displayMode = "alwaysShow";
  };

  noctalia = inputs.nix-wrapper-modules.wrappers.noctalia-shell.wrap {
    inherit pkgs;

    # No `outOfStoreConfig`: nix is authoritative, so the settings panel can no
    # longer save — change settings here, not in the GUI.

    settings = {
      bar = {
        barType = "simple";
        inherit (cfg.bar) position density;

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

        widgets = {
          left =
            map widget ["Workspace" "ActiveWindow"]
            ++ [
              (widget "MediaMini")
              # Only draws while the mic, camera or a screencast is live.
              (pluginWidget "privacy-indicator")
            ];
          center = map widget ["Clock"];
          right =
            map valueWidget ["Volume" "Brightness"]
            ++ map widget ["Network" "Bluetooth"]
            ++ [
              # Replaces kdeconnect-indicator's tray icon, off in plugins.nix.
              (pluginWidget "kde-connect")
              (pluginWidget "protonvpn")
              (pluginWidget "netbird")
              (pluginWidget "thinkpad-fan")
            ]
            # `hideIfNotDetected` relies on UPower seeing the battery (desktop.power).
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
                # Two rules: noctalia matches the tooltip title when present, else the
                # item id. The applet keeps running — it is also the pairing agent.
                blacklist = ["blueman" "Bluetooth*"];
              }
            ]
            ++ map widget ["NotificationHistory" "ControlCenter"];
          # battery-monitor-plus and model-usage have bar widgets but no slot —
          # add `plugin:<id>` here to surface them.
        };
      };

      # FIVE PER SIDE max: ShortcutsCard doesn't wrap, a sixth renders outside
      # the card. Plugins need a `controlCenterWidget` entry point to show here.
      controlCenter.shortcuts = {
        left =
          map widget ["Network" "Bluetooth" "WallpaperSelector" "NoctaliaPerformance"]
          ++ [(pluginWidget "screen-toolkit")];
        right =
          # No DND slot: kde-connect's control-centre widget is the only way to
          # reach it with the phone off the network. DND stays on IPC `toggleDND`.
          map widget ["PowerProfile" "KeepAwake" "NightLight"]
          ++ [
            (pluginWidget "kde-connect")
            (pluginWidget "plugin-manager")
          ];
      };

      dock.enabled = false;

      colorSchemes = {
        predefinedScheme = "Nord";
        darkMode = true;
        useWallpaperColors = false;
      };

      # Blur via `ext-background-effect` (niri 26.04 implements it); notifications,
      # OSDs and toasts stay unblurred (see _niri/system.nix).
      general = {
        enableShadows = false;
        enableBlurBehind = true;
        showScreenCorners = false;
        showChangelogOnStartup = false;

        # Without `allowPasswordWithFprintd` a failed/absent finger locks out typing.
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
        # Not stylix's sansSerif: mixing in DejaVu made the shell look off.
        fontDefault = fonts.interface.name;
        fontFixed = fonts.monospace.name;
        panelBackgroundOpacity = opacity.desktop;
        # Only the panel *background* is translucent; stacking a second level
        # turns frosted glass into an unreadable smear.
        translucentWidgets = false;
      };

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

      osd.backgroundOpacity = opacity.popups;

      wallpaper.directory = wallpapers.directory;

      location = {
        name = "Eindhoven";
        autoLocate = false;
      };
    };
  };

  # The wallpaper is runtime state in noctalia's cache; settings.json can't set a default.
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
      # Holds the picked wallpaper; losing it resets the background.
      ".cache/noctalia"
    ];

    home.activation.noctaliaDefaultWallpaper = lib.hm.dag.entryAfter ["writeBoundary"] ''
      _cache=${lib.escapeShellArg "${config.xdg.cacheHome}/noctalia"}
      if [ ! -e "$_cache/wallpapers.json" ]; then
        run mkdir -p "$_cache"
        run cp ${pkgs.writeText "noctalia-wallpapers.json" wallpaperCache} "$_cache/wallpapers.json"
        run chmod u+w "$_cache/wallpapers.json"
      fi
    '';

    systemd.user.services.noctalia = {
      Unit = {
        Description = "noctalia shell";
        PartOf = ["graphical-session.target"];
        After = ["graphical-session.target"];
      };
      Service = {
        ExecStart = lib.getExe noctalia;
        # Deterministic PAM stack: `login` is where services.fprintd wires pam_fprintd.
        Environment = ["NOCTALIA_PAM_SERVICE=login"];
        Restart = "on-failure";
        RestartSec = 2;
        Slice = "session.slice";
      };
      Install.WantedBy = ["graphical-session.target"];
    };
  };
}
