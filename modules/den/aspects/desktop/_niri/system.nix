# The niri system config, as a plain NixOS module *factory*.
#
# Imported by BOTH `den.aspects.desktop.niri` (see ../niri.nix) and voyager's
# `specialisation.niri` — specialisation bodies are ordinary NixOS modules and
# cannot `include` a den aspect, so the shared content lives here and is applied
# from both places. Call it as `import ./_niri/system.nix {inherit inputs;}`.
{inputs}: {
  config,
  lib,
  pkgs,
  ...
}: let
  colors = config.lib.stylix.colors.withHashtag;

  # Resolved from PATH at runtime so the compositor is not coupled to the
  # user-scoped noctalia package (see home.noctalia).
  noctalia = target: action: "noctalia-shell ipc call ${target} ${action}";

  # No foot server runs under niri, so use the standalone binary.
  terminal = "foot";

  # What a *tap* of the Mod key produces, courtesy of keyd's overload (see
  # desktop/keyd.nix). Holding Mod is unaffected, so this is free to bind.
  modTap = config.cosmos.desktops.input.modTap.keysym;

  # A bind that still fires while the screen is locked. `allow-when-locked` is a
  # KDL *property* of the bind node, so it goes in `props`, with the action as
  # the node's content.
  locked = action: _: {
    props.allow-when-locked = true;
    content = action;
  };

  # Workspace keys, matching the Hyprland config's `code:10`..`code:18`.
  #
  # niri binds by XKB *key name* and has no keycode escape hatch, so we cannot
  # say "physical key 1" directly. Under Programmer Dvorak (us/dvp) the number
  # row's digits are both shifted AND reordered (Shift gives 7 5 3 1 9 0 2 4 6),
  # so `Mod+1` would land on the physical 5 key. Binding the row's *unshifted*
  # keysyms instead hits exactly the physical keys Hyprland's keycodes did.
  #
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

    # Opt out of the v1 compatibility layer: it warns on the legacy `null` /
    # `_attrs` idioms, and this flake runs with abort-on-warn.
    v2-settings = true;

    settings = {
      # Mirrors the Hyprland input block (_hyprland/settings.nix).
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
        # Hyprland's follow_mouse = 2.
        focus-follows-mouse = _: {};
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

        # Tuning only — deliberately no `on`, so nothing casts a shadow by
        # default. The floating-window rule below is what switches it on, and
        # it is the only rule that does.
        shadow = {
          softness = 20;
          spread = 2;
          offset = _: {
            props = {
              x = 0;
              y = 4;
            };
          };
          # Tinted with the scheme's darkest background rather than pure black,
          # so it reads as depth in the palette instead of a grey smudge.
          color = "${colors.base00}a0";
        };
      };

      # Nine permanent workspaces, like Hyprland's. niri's workspaces are
      # normally dynamic (created/destroyed on demand); *named* ones always
      # exist even when empty, so declaring "1".."9" keeps all nine live.
      workspaces = lib.listToAttrs (
        map (i: {
          name = toString i;
          value = _: {};
        }) (lib.range 1 9)
      );

      prefer-no-csd = true;
      screenshot-path = "~/Pictures/screenshots/%Y-%m-%d %H-%M-%S.png";
      hotkey-overlay.skip-at-startup = [];

      environment.NIXOS_OZONE_WL = "1";

      # Ported from the Hyprland binds (_hyprland/binds.nix): same keys, same
      # modifiers, niri's equivalent actions.
      binds =
        {
          # Compositor
          "Mod+Shift+Q".quit = _: {};
          "Mod+Shift+C".close-window = _: {};
          "Mod+T".toggle-window-floating = _: {};
          # (Hyprland's Mod+D toggle_swallow has no niri equivalent.)

          # Three different things in niri, where Hyprland had one. Mod+F keeps
          # Hyprland's meaning; the other two take the keys niri itself uses.
          #
          #   Mod+F        fullscreen — covers the screen, bar and gaps gone
          #   Mod+M        maximize the WINDOW to the edges of the working
          #                area: the bar stays, struts/gaps/borders do not,
          #                and the window is *told* it is maximized so it
          #                squares its own corners like it would anywhere else
          #   Mod+Shift+M  maximize the COLUMN — full width, gaps and borders
          #                kept, and it can still hold several windows
          "Mod+F".fullscreen-window = _: {};
          "Mod+M".maximize-window-to-edges = _: {};
          "Mod+Shift+M".maximize-column = _: {};

          # Tells a window it is fullscreen without making it fullscreen. A
          # browser drops its chrome for a slide deck while staying a normal
          # resizable window, so a screencast can frame it next to the notes
          # instead of surrendering the whole monitor to it.
          "Mod+Ctrl+F".toggle-windowed-fullscreen = _: {};

          # Move focus
          "Mod+L".focus-column-right = _: {};
          "Mod+H".focus-column-left = _: {};
          "Mod+K".focus-window-up = _: {};
          "Mod+J".focus-window-down = _: {};

          # Move window
          "Mod+Shift+L".move-column-right = _: {};
          "Mod+Shift+H".move-column-left = _: {};
          "Mod+Shift+K".move-window-up = _: {};
          "Mod+Shift+J".move-window-down = _: {};

          # Resize window
          "Mod+Ctrl+L".set-column-width = "+10%";
          "Mod+Ctrl+H".set-column-width = "-10%";
          "Mod+Ctrl+K".set-window-height = "-10%";
          "Mod+Ctrl+J".set-window-height = "+10%";

          # Put more than one window in a column — niri's answer to both
          # "split vertically" and "stack", which are the same thing here:
          # a column holding several windows, drawn either shared or tabbed.
          # Nothing above can create that state, so without these the
          # focus-window-up/down and move-window-up/down binds are
          # unreachable in practice.
          #
          # Not Mod+BracketLeft/Right as upstream niri binds them. On
          # Programmer Dvorak the brackets sit on the number row — [ at the
          # physical 2 key, ] at the physical 0 — where the workspace binds
          # below already live, so those would collide.
          #
          # Comma and Period are adjacent on dvp's top letter row (";,.pyf"),
          # left hand, and free. They are also what the niri docs use for this
          # action, so what is written there matches what is bound here.
          "Mod+Comma".consume-or-expel-window-left = _: {};
          "Mod+Period".consume-or-expel-window-right = _: {};

          # Flip that column between tabbed and shared. `default-column-display`
          # above is "tabbed", so a new column stacks; this is how to get an
          # actual vertical split for the one column that wants it.
          "Mod+W".toggle-column-tabbed-display = _: {};

          # Power menu / lock
          "Mod+Escape".spawn-sh = noctalia "sessionMenu" "toggle";
          "Mod+Shift+Escape".spawn-sh = noctalia "lockScreen" "lock";

          # Tapping Mod on its own opens the control centre. `keyd monitor`
          # shows the tap arriving with no modifier held —
          #
          #   leftmeta down, leftcontrol down,     <- keyd's modifier guard
          #   leftmeta up,   leftcontrol up,
          #   f19 down,      f19 up
          #
          # so the unmodified form is the only one that can ever match; a
          # `Mod+` variant was dead weight.
          ${modTap}.spawn-sh = noctalia "controlCenter" "toggle";

          # Utilities
          "Mod+Shift+Return".spawn = terminal;
          "Mod+Tab".spawn-sh = noctalia "launcher" "toggle";
          "Alt+Tab".toggle-overview = _: {};
          "Mod+V".spawn-sh = noctalia "launcher" "toggle"; # clipboard lives in the launcher
          "Mod+S".screenshot = _: {};
          "Mod+Shift+S".screenshot-window = _: {};

          # Screencasting. The plumbing already works — programs.niri ships the
          # gnome portal and desktop.audio the pipewire stack — so what is
          # bound here is niri's own casting feature: a stream that appears in
          # the portal picker as "niri Dynamic Cast Target". Share it once,
          # then re-aim it from the keyboard without going back through the
          # sharing dialog. Each new cast starts out empty regardless of where
          # this last pointed, so selecting it can never reveal something by
          # accident.
          "Mod+C".set-dynamic-cast-window = _: {};
          "Mod+Ctrl+C".set-dynamic-cast-monitor = _: {};
          "Mod+Ctrl+Shift+C".clear-dynamic-cast-target = _: {};

          # The Print key keeps working too (niri's own defaults).
          "Print".screenshot = _: {};
          "Ctrl+Print".screenshot-screen = _: {};
          "Alt+Print".screenshot-window = _: {};

          # Calculator, on Hyprland's key. qalc does units/currency/bases;
          # opens in a floating terminal (see the window-rule below).
          "Alt+Shift+Return".spawn = "calculator";

          # niri extras with no Hyprland counterpart
          "Mod+R".switch-preset-column-width = _: {};
          "Mod+O".toggle-overview = _: {};
          "Mod+Shift+Slash".show-hotkey-overlay = _: {};

          # noctalia plugins that ship no bar widget slot. Their IPC targets are
          # namespaced `plugin:<id>`, same as their bar widgets.
          "Mod+Slash".spawn-sh = noctalia "plugin:keybind-cheatsheet" "toggle";
          "Mod+P".spawn-sh = noctalia "plugin:display-settings" "toggle";
          "Mod+Shift+P".spawn-sh = noctalia "plugin:screen-toolkit" "colorPicker";
          # No control-centre slot for this one: the shortcuts card only accepts
          # plugins that declare a `controlCenterWidget` entry point, and
          # battery-threshold ships only a bar widget.
          "Mod+Shift+B".spawn-sh = noctalia "plugin:battery-threshold" "togglePanel";

          # Brightness / audio / media — `allow-when-locked` is a property on the
          # bind node itself, so these use the wrapper's props/content form.
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
          # Depth, where the rest of the layout is flat. A floating window sits
          # *on top of* the tiled columns with nothing else to separate the
          # two, and the shadow is what says which is which. Tiled windows are
          # left flat on purpose — they tile, so they need no separating.
          shadow.on = _: {};
        }
        # The calculator pops up floating, rofi-calc style.
        {
          matches = [{app-id = "^calculator$";}];
          open-floating = true;
        }
        # Drawn as a solid black rectangle in screencasts. Deliberately
        # "screencast" and not "screen-capture": the latter would also blank
        # these in screenshots, and a screenshot is something you took on
        # purpose.
        #
        # The app-ids are each package's StartupWMClass, read off the desktop
        # file rather than guessed — a wrong id here fails *silently* and the
        # window is shared anyway, which is the one failure mode this rule
        # exists to prevent.
        {
          matches = [
            {app-id = "^signal$";}
            {app-id = "^discord$";}
          ];
          block-out-from = "screencast";
        }
        # Whatever is actually being cast turns red, so there is never a
        # question about which window the far end can see. Matches only the
        # target of a *window* cast (the dynamic target above included); a
        # whole-monitor cast has no window to mark and cannot be indicated
        # this way.
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

      # Layer-shell surfaces — noctalia's bar, panels and notifications — are
      # not windows, so no window rule above ever sees them.
      layer-rules = [
        # Notification and toast popups carry message previews, and blocking
        # them out covers the case the window rule above cannot: the
        # notification for a Signal message is drawn by noctalia, not by
        # Signal, so blocking Signal's window does nothing for it.
        #
        # noctalia namespaces its surfaces `noctalia-<kind>-<output>`, hence
        # matching the prefix including the trailing dash.
        {
          matches = [
            {namespace = "^noctalia-notifications-";}
            {namespace = "^noctalia-toast-";}
          ];
          block-out-from = "screencast";
        }
      ];
    };
  };
in {
  environment.sessionVariables.NIXOS_OZONE_WL = "1";

  programs.niri = {
    enable = true;
    package = niri;
    # The FileChooser portal falls back to gtk without it; keeps nautilus (and
    # half of GNOME) out of the closure.
    useNautilus = false;
  };

  # programs.niri turns gnome-keyring on by default, whose ssh-agent component
  # collides with core.ssh's `programs.ssh.startAgent`. We already run
  # gnome-keyring as a user service where it is wanted (home.keyring).
  services.gnome.gnome-keyring.enable = lib.mkForce false;

  environment.systemPackages = with pkgs; [
    # niri autostarts xwayland-satellite from $PATH (on by default since 25.05),
    # but the module does not install it.
    xwayland-satellite
    wl-clipboard
    # referenced by the binds below (same tools the Hyprland binds use)
    brightnessctl
    pamixer
    playerctl
  ];

  # programs.niri turns polkit on but ships no authentication agent. That job is
  # now noctalia's `polkit-agent` plugin (see _noctalia/plugins.nix) — only one
  # process can hold the polkit agent registration, so a standalone
  # hyprpolkitagent unit here would race it and one of the two would lose.
  #
  # The trade-off: no agent runs before noctalia is up. In this specialisation
  # noctalia is the session shell, so that window is the same one in which
  # nothing could prompt anyway.

  # One entry in the greeter (see desktop/greetd.nix for why it is curated).
  cosmos.profiles.desktop.addons.greetd.sessions = [
    {
      name = "niri.desktop";
      path = "${config.programs.niri.package}/share/wayland-sessions/niri.desktop";
    }
  ];
}
