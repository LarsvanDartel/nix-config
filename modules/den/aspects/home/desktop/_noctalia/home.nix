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

  widget = id: {inherit id;};

  noctalia = inputs.nix-wrapper-modules.wrappers.noctalia-shell.wrap {
    inherit pkgs;

    # Seed the generated config into a writable location so noctalia's own
    # settings panel keeps working; existing files are never overwritten.
    outOfStoreConfig = "${config.xdg.configHome}/noctalia";
    autoCopyConfig = true;

    settings = {
      bar = {
        barType = "simple";
        inherit (cfg.bar) position density;

        # flat + edge-to-edge: no capsule pills, no rounding, no margins
        showCapsule = false;
        showOutline = false;
        backgroundOpacity = 1.0;
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
          left = map widget ["Workspace" "ActiveWindow"];
          center = map widget ["Clock"];
          right =
            map widget ["MediaMini" "Volume" "Brightness" "Network" "Bluetooth"]
            # `icon-always` keeps the pill open, so the charge percentage shows
            # permanently instead of only on hover.
            ++ [
              {
                id = "Battery";
                displayMode = "icon-always";
              }
            ]
            ++ map widget ["Tray" "NotificationHistory" "ControlCenter"];
          # Night light, keep-awake and the wallpaper picker stay *enabled* —
          # they just live in the control centre rather than on the bar.
        };
      };

      # Built-in Nord scheme — the same base16 palette stylix themes the rest with.
      colorSchemes = {
        predefinedScheme = "Nord";
        darkMode = true;
        useWallpaperColors = false;
      };

      # Minimal chrome: flat, no shadows or blur, no faux screen corners.
      general = {
        enableShadows = false;
        enableBlurBehind = false;
        showScreenCorners = false;
        showChangelogOnStartup = false;
      };

      ui = {
        fontDefault = config.stylix.fonts.sansSerif.name;
        fontFixed = config.stylix.fonts.monospace.name;
        panelBackgroundOpacity = 1.0;
        translucentWidgets = false;
      };

      appLauncher = {
        enableClipboardHistory = cfg.widgets.clipboardHistory;
        terminalCommand = "${config.cosmos.cli.terminals.defaultStandalone} -e";
      };

      # DDC/CI, so the brightness widget also drives an external monitor.
      brightness.enableDdcSupport = cfg.widgets.externalBrightness;

      nightLight = {
        enabled = cfg.widgets.nightLight;
        autoSchedule = true;
      };

      idle.enabled = cfg.widgets.idleInhibitor;

      notifications.enabled = cfg.notifications.enable;

      # Backgrounds the wallpaper picker browses (see home.wallpapers).
      wallpaper.directory = config.cosmos.desktops.wallpapers.directory;

      # Drives the weather widget and the night light's sunrise/sunset schedule.
      # Pinned rather than geolocated, so it works offline and doesn't phone out.
      location = {
        name = "Eindhoven";
        autoLocate = false;
      };
    };
  };
in {
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

    cosmos.system.impermanence.persist.directories = [".config/noctalia"];

    # Compositor-agnostic autostart: both niri and Hyprland/UWSM reach this target.
    systemd.user.services.noctalia = {
      Unit = {
        Description = "noctalia shell";
        PartOf = ["graphical-session.target"];
        After = ["graphical-session.target"];
      };
      Service = {
        ExecStart = lib.getExe noctalia;
        Restart = "on-failure";
        RestartSec = 2;
        Slice = "session.slice";
      };
      Install.WantedBy = ["graphical-session.target"];
    };
  };
}
