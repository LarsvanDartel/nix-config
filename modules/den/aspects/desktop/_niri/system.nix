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

  terminal = "foot";

  niri = inputs.nix-wrapper-modules.wrappers.niri.wrap {
    inherit pkgs;

    # nixpkgs-unstable's niri 26.04 does not build: it vendors
    # libdisplay-info-sys 0.3.0, which requires `libdisplay-info < 0.4.0`, while
    # unstable ships 0.4.0. The stable channel pairs niri 25.11 with
    # libdisplay-info 0.3.0, and is in the binary cache.
    # TODO: drop this pin once nixpkgs-unstable's niri builds again.
    package = pkgs.stable.niri;

    # Opt out of the v1 compatibility layer: it warns on the legacy `null` /
    # `_attrs` idioms, and this flake runs with abort-on-warn.
    v2-settings = true;

    settings = {
      input = {
        keyboard.xkb = {
          inherit (config.services.xserver.xkb) layout variant options;
        };
        touchpad = {
          tap = _: {};
          natural-scroll = _: {};
          dwt = _: {};
        };
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
        focus-ring = {
          width = 2;
          active-color = colors.base0D;
          inactive-color = colors.base02;
        };
        border.off = _: {};
      };

      prefer-no-csd = true;
      screenshot-path = "~/Pictures/screenshots/%Y-%m-%d %H-%M-%S.png";
      hotkey-overlay.skip-at-startup = [];

      environment.NIXOS_OZONE_WL = "1";

      binds = {
        "Mod+Shift+Slash".show-hotkey-overlay = _: {};

        # launching — the shell's parts are reached over noctalia's IPC
        "Mod+Return".spawn = terminal;
        "Mod+D".spawn-sh = noctalia "launcher" "toggle";
        "Mod+N".spawn-sh = noctalia "notifications" "toggleHistory";
        "Mod+C".spawn-sh = noctalia "controlCenter" "toggle";
        "Super+Alt+L".spawn-sh = noctalia "lockScreen" "lock";
        "Mod+Shift+E".spawn-sh = noctalia "sessionMenu" "toggle";

        # windows
        "Mod+Q".close-window = _: {};
        "Mod+H".focus-column-left = _: {};
        "Mod+L".focus-column-right = _: {};
        "Mod+J".focus-window-down = _: {};
        "Mod+K".focus-window-up = _: {};
        "Mod+Ctrl+H".move-column-left = _: {};
        "Mod+Ctrl+L".move-column-right = _: {};
        "Mod+Ctrl+J".move-window-down = _: {};
        "Mod+Ctrl+K".move-window-up = _: {};

        "Mod+R".switch-preset-column-width = _: {};
        "Mod+F".maximize-column = _: {};
        "Mod+Shift+F".fullscreen-window = _: {};
        "Mod+V".toggle-window-floating = _: {};
        "Mod+O".toggle-overview = _: {};

        # workspaces
        "Mod+1".focus-workspace = 1;
        "Mod+2".focus-workspace = 2;
        "Mod+3".focus-workspace = 3;
        "Mod+4".focus-workspace = 4;
        "Mod+Ctrl+1".move-column-to-workspace = 1;
        "Mod+Ctrl+2".move-column-to-workspace = 2;
        "Mod+Ctrl+3".move-column-to-workspace = 3;
        "Mod+Ctrl+4".move-column-to-workspace = 4;
        "Mod+U".focus-workspace-down = _: {};
        "Mod+I".focus-workspace-up = _: {};

        # screenshots
        "Print".screenshot = _: {};
        "Ctrl+Print".screenshot-screen = _: {};
        "Alt+Print".screenshot-window = _: {};

        # media / hardware keys
        "XF86AudioRaiseVolume".spawn = ["wpctl" "set-volume" "@DEFAULT_AUDIO_SINK@" "5%+"];
        "XF86AudioLowerVolume".spawn = ["wpctl" "set-volume" "@DEFAULT_AUDIO_SINK@" "5%-"];
        "XF86AudioMute".spawn = ["wpctl" "set-mute" "@DEFAULT_AUDIO_SINK@" "toggle"];
        "XF86AudioMicMute".spawn = ["wpctl" "set-mute" "@DEFAULT_AUDIO_SOURCE@" "toggle"];
        "XF86MonBrightnessUp".spawn = ["brightnessctl" "set" "5%+"];
        "XF86MonBrightnessDown".spawn = ["brightnessctl" "set" "5%-"];
        "XF86AudioPlay".spawn = ["playerctl" "play-pause"];
        "XF86AudioNext".spawn = ["playerctl" "next"];
        "XF86AudioPrev".spawn = ["playerctl" "previous"];

        "Ctrl+Alt+Delete".quit = _: {};
      };

      window-rules = [
        {
          matches = [{is-floating = true;}];
          geometry-corner-radius = 6.0;
          clip-to-geometry = true;
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
    brightnessctl
    playerctl
  ];

  # programs.niri turns polkit on but ships no authentication agent.
  systemd.user.services.hyprpolkitagent = {
    description = "polkit authentication agent";
    wantedBy = ["graphical-session.target"];
    partOf = ["graphical-session.target"];
    after = ["graphical-session.target"];
    serviceConfig = {
      Type = "simple";
      ExecStart = lib.getExe' pkgs.hyprpolkitagent "hyprpolkitagent";
      Restart = "on-failure";
      Slice = "session.slice";
    };
  };

  # One entry in the greeter (see desktop/greetd.nix for why it is curated).
  cosmos.profiles.desktop.addons.greetd.sessions = [
    {
      name = "niri.desktop";
      path = "${config.programs.niri.package}/share/wayland-sessions/niri.desktop";
    }
  ];
}
