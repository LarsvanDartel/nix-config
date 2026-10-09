# The niri system config, as a plain NixOS module factory shared by
# `den.aspects.desktop.niri` and voyager's `specialisation.niri`.
{inputs}: {
  config,
  lib,
  pkgs,
  ...
}: let
  colors = config.lib.stylix.colors.withHashtag;

  # Resolved from PATH so the compositor isn't coupled to user-scoped noctalia.
  noctalia = target: action: "noctalia-shell ipc call ${target} ${action}";

  # No foot server runs under niri, so use the standalone binary.
  terminal = "foot";

  modTap = config.cosmos.desktops.input.modTap.keysym;

  # `allow-when-locked` is a KDL property, so it goes in `props`.
  locked = action: _: {
    props.allow-when-locked = true;
    content = action;
  };

  # niri binds by keysym, and us/dvp shifts and reorders the digit row, so bind
  # the row's unshifted keysyms to hit the physical keys:
  #   physical:  1  2  3  4  5  6  7  8  9
  #   us(dvp):   &  [  {  }  (  =  *  )  +
  workspaceKeys = [
    "ampersand"
    "bracketleft"
    "braceleft"
    "braceright"
    "parenleft"
    "equal"
    "asterisk"
    "parenright"
    "plus"
  ];

  # Refer to the workspaces by NAME (see `workspaces` below): named workspaces
  # always exist, so 1..9 are permanently available like Hyprland's.
  workspaceBinds = lib.listToAttrs (
    lib.flatten (
      lib.imap1 (i: key: let
        ws = toString i;
      in [
        {
          name = "Mod+${key}";
          value.focus-workspace = ws;
        }
        {
          name = "Mod+Shift+${key}";
          value.move-column-to-workspace = ws;
        }
      ])
      workspaceKeys
    )
  );

  niri = inputs.nix-wrapper-modules.wrappers.niri.wrap {
    inherit pkgs;

    settings = {
      input = {
        keyboard = {
          xkb = {
            layout = "us,us";
            variant = "dvp,intl";
            options = "caps:escape,grp:win_space_toggle";
          };
          repeat-delay = 300;
          repeat-rate = 20;
        };
        touchpad = {
          tap = _: {};
          natural-scroll = _: {};
          scroll-factor = 0.2;
          accel-profile = "flat";
        };
        mouse = {
          accel-profile = "flat";
          accel-speed = 0.0;
        };
        # No focus-follows-mouse: niri has no equivalent of Hyprland's
        # detached `follow_mouse = 2`.
      };

      layout = {
        gaps = 8;
        center-focused-column = "never";
        default-column-width.proportion = 0.5;
        preset-column-widths = [
          {proportion = 1.0 / 3.0;}
          {proportion = 0.5;}
          {proportion = 2.0 / 3.0;}
        ];
        default-column-display = "tabbed";
        tab-indicator = {
          hide-when-single-tab = _: {};
        };
        focus-ring = {
          width = 2;
          active-color = colors.base0D;
          inactive-color = colors.base02;
        };
        border.off = _: {};

        # Deliberately no `on`: only the floating-window rule enables shadows.
        shadow = {
          softness = 20;
          spread = 2;
          offset = _: {
            props = {
              x = 0;
              y = 4;
            };
          };
          color = "${colors.base00}a0";
        };
      };

      # Named niri workspaces always exist, giving nine permanent ones.
      workspaces = lib.listToAttrs (
        map (i: {
          name = toString i;
          value = _: {};
        }) (lib.range 1 9)
      );

      # foot can't request blur (see window rule); other surfaces ask via
      # ext-background-effect.
      blur = {
        passes = 4;
        noise = 0.01;
      };

      prefer-no-csd = true;
      screenshot-path = "~/Pictures/screenshots/%Y-%m-%d %H-%M-%S.png";
      hotkey-overlay.skip-at-startup = [];

      environment.NIXOS_OZONE_WL = "1";

      binds =
        {
          "Mod+Shift+Q".quit = _: {};
          "Mod+Shift+C".close-window = _: {};
          "Mod+T".toggle-window-floating = _: {};

          # Mod+M maximizes the window (told it is maximized); Mod+Shift+M the
          # column.
          "Mod+F".fullscreen-window = _: {};
          "Mod+M".maximize-window-to-edges = _: {};
          "Mod+Shift+M".maximize-column = _: {};

          "Mod+Ctrl+F".toggle-windowed-fullscreen = _: {};

          "Mod+L".focus-column-right = _: {};
          "Mod+H".focus-column-left = _: {};
          "Mod+K".focus-window-up = _: {};
          "Mod+J".focus-window-down = _: {};

          "Mod+Shift+L".move-column-right = _: {};
          "Mod+Shift+H".move-column-left = _: {};
          "Mod+Shift+K".move-window-up = _: {};
          "Mod+Shift+J".move-window-down = _: {};

          "Mod+Ctrl+L".set-column-width = "+10%";
          "Mod+Ctrl+H".set-column-width = "-10%";
          "Mod+Ctrl+K".set-window-height = "-10%";
          "Mod+Ctrl+J".set-window-height = "+10%";

          # Only way to build a multi-window column. Not upstream's brackets:
          # on dvp they sit on the workspace row.
          "Mod+Comma".consume-or-expel-window-left = _: {};
          "Mod+Period".consume-or-expel-window-right = _: {};

          # default-column-display is "tabbed"; this is how a column gets split.
          "Mod+W".toggle-column-tabbed-display = _: {};

          "Mod+Escape".spawn-sh = noctalia "sessionMenu" "toggle";
          "Mod+Shift+Escape".spawn-sh = noctalia "lockScreen" "lock";

          # keyd delivers the tap unmodified, so only the bare form can match.
          ${modTap}.spawn-sh = noctalia "controlCenter" "toggle";

          "Mod+Shift+Return".spawn = terminal;
          "Mod+Tab".spawn-sh = noctalia "launcher" "toggle";
          "Alt+Tab".toggle-overview = _: {};
          "Mod+V".spawn-sh = noctalia "launcher" "toggle"; # clipboard lives in the launcher
          "Mod+S".screenshot = _: {};
          "Mod+Shift+S".screenshot-window = _: {};

          "Mod+C".set-dynamic-cast-window = _: {};
          "Mod+Ctrl+C".set-dynamic-cast-monitor = _: {};
          "Mod+Ctrl+Shift+C".clear-dynamic-cast-target = _: {};

          "Print".screenshot = _: {};
          "Ctrl+Print".screenshot-screen = _: {};
          "Alt+Print".screenshot-window = _: {};

          "Alt+Shift+Return".spawn = "calculator";

          "Mod+R".switch-preset-column-width = _: {};
          "Mod+O".toggle-overview = _: {};
          "Mod+Shift+Slash".show-hotkey-overlay = _: {};

          # Plugin IPC targets are namespaced `plugin:<id>`.
          "Mod+Slash".spawn-sh = noctalia "plugin:keybind-cheatsheet" "toggle";
          "Mod+P".spawn-sh = noctalia "plugin:display-settings" "toggle";
          "Mod+Shift+P".spawn-sh = noctalia "plugin:screen-toolkit" "colorPicker";
          # battery-threshold has no controlCenterWidget, so no control-centre slot.
          "Mod+Shift+B".spawn-sh = noctalia "plugin:battery-threshold" "togglePanel";

          "XF86MonBrightnessUp" = locked {spawn = ["brightnessctl" "set" "+5%"];};
          "XF86MonBrightnessDown" = locked {spawn = ["brightnessctl" "set" "5%-"];};

          "XF86AudioRaiseVolume" = locked {spawn = ["pamixer" "-i" "5"];};
          "XF86AudioLowerVolume" = locked {spawn = ["pamixer" "-d" "5"];};
          "XF86AudioMute" = locked {spawn = ["pamixer" "--toggle-mute"];};
          "XF86AudioMicMute" = locked {spawn = ["pamixer" "--default-source" "--toggle-mute"];};

          "XF86AudioNext" = locked {spawn = ["playerctl" "next"];};
          "XF86AudioPrev" = locked {spawn = ["playerctl" "previous"];};
          "XF86AudioPlay" = locked {spawn = ["playerctl" "play-pause"];};
          "XF86AudioStop" = locked {spawn = ["playerctl" "stop"];};
        }
        // workspaceBinds;

      window-rules = [
        {
          matches = [{is-floating = true;}];
          geometry-corner-radius = 6.0;
          clip-to-geometry = true;
          shadow.on = _: {};
        }
        # foot cannot request blur itself. `xray false` is still experimental.
        {
          matches = [{app-id = "^foot$";}];
          background-effect.blur = true;
        }
        {
          matches = [{app-id = "^calculator$";}];
          open-floating = true;
        }
        # "screencast", not "screen-capture" (which also blanks screenshots).
        # app-ids are StartupWMClass; a wrong id fails silently.
        {
          matches = [
            {app-id = "^signal$";}
            {app-id = "^discord$";}
          ];
          block-out-from = "screencast";
        }
        # Red ring on whatever window is being cast.
        {
          matches = [{is-window-cast-target = true;}];
          focus-ring = {
            active-color = colors.base08;
            inactive-color = "${colors.base08}80";
          };
          tab-indicator = {
            active-color = colors.base08;
            inactive-color = "${colors.base08}80";
          };
        }
      ];

      # noctalia's popups aren't windows, so window rules don't see them.
      layer-rules = [
        # Blocking Signal's window does not cover noctalia-drawn previews.
        {
          matches = [
            {namespace = "^noctalia-notifications-";}
            {namespace = "^noctalia-toast-";}
          ];
          block-out-from = "screencast";
        }
        # Deliberately NO layer-rule blur (tried, reverted): noctalia's popups
        # are padded larger than the card, so whole-surface blur draws a big
        # box around every notification. Fix belongs in noctalia (blurRegion).
      ];
    };
  };
in {
  environment.sessionVariables.NIXOS_OZONE_WL = "1";

  programs.niri = {
    enable = true;
    package = niri;
    # Else the FileChooser portal pulls nautilus into the closure.
    useNautilus = false;
  };

  environment.systemPackages = with pkgs; [
    # niri autostarts it from $PATH but the module does not install it.
    xwayland-satellite
    wl-clipboard
    brightnessctl
    pamixer
    playerctl
  ];

  # No polkit agent here: noctalia's polkit-agent plugin holds the
  # registration and a second agent would race it.

  cosmos.profiles.desktop.addons.greetd.sessions = [
    {
      name = "niri.desktop";
      path = "${config.programs.niri.package}/share/wayland-sessions/niri.desktop";
    }
  ];

  # Not gated like hyprland.nix: this module is only loaded when niri is active.
  cosmos.profiles.desktop.lockCommand = noctalia "lockScreen" "lock";
}
