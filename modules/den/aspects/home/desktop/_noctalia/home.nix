# The noctalia v5 home config (home-manager's `programs.noctalia`), as a plain
# home-manager module factory: also imported by voyager's `specialisation.niri`,
# which cannot `include` a den aspect.
{inputs}: {
  config,
  lib,
  ...
}: let
  fonts = config.cosmos.desktops.common.styling.fonts;
  # Not stylix's sansSerif: mixing in DejaVu made the shell look off. The vector cut,
  # which the fontconfig pixel-grid rule (_styling/fonts/fontconfig) snaps to 13px multiples.
  font = fonts.pkgs."Cozette Vector";
  opacity = config.stylix.opacity;
  wallpapers = config.cosmos.desktops.wallpapers;
in {
  imports = [(import ./plugins.nix {inherit inputs;})];

  # Colours, theme mode and popup opacity come from stylix's `noctalia` target.
  programs.noctalia = {
    enable = true;
    systemd.enable = true;
    settings = {
      bar.default = {
        position = "top";
        thickness = 25;
        background_opacity = opacity.desktop;
        radius = 0;
        radius_top_left = 0;
        radius_top_right = 0;
        radius_bottom_left = 0;
        radius_bottom_right = 0;
        concave_edge_corners = false;
        margin_ends = 0;
        margin_edge = 0;
        padding = 2;
        widget_spacing = 6;
        shadow = false;
        capsule = true;
        # surface_variant barely separates from the bar; outline is the next Nord shade up.
        capsule_fill = "outline";
        start = ["workspaces" "active_window" "media" "privacy"];
        center = ["clock"];
        end = [
          "volume"
          "brightness"
          "network"
          "bluetooth"
          "phone"
          "netbird"
          "fan"
          "battery"
          "tray"
          "notifications"
          "control-center"
        ];
      };

      widget = {
        clock.format = "{:%H:%M %a, %b %d}";
        volume.show_label = true;
        brightness.show_label = true;
        battery = {
          display_mode = "glyph";
          show_label = true;
          label_content = "percent";
        };
        # Only draws while the mic, camera or a screencast is live.
        privacy.hide_inactive = true;
        workspaces = {
          # stylix's Nord secondary is purple; tertiary is the cyan v4's Nord scheme used.
          occupied_color = "tertiary";
          empty_color = "tertiary";
          labels_only_when_occupied = true;
        };
        # The applet keeps running: it is also the pairing agent.
        tray.hidden = ["blueman"];
        phone.type = "icefish/phone-connect:bar";
        netbird.type = "lvdar/netbird:status";
        fan.type = "piero-93/thinkpad-fan:widget";
      };

      # Six at most. No DND tile: DND stays on the notifications widget's right-click.
      control_center.shortcuts = map (type: {inherit type;}) [
        "wifi"
        "bluetooth"
        "power_profile"
        "caffeine"
        "nightlight"
        "icefish/phone-connect:tile"
      ];

      shell = {
        font_family = lib.mkForce font.name;
        setup_wizard_enabled = false;
        polkit_agent = true;
        niri_overview_type_to_launch_enabled = true;
        launcher = {
          compact = true;
          categories = false;
        };
        panel = {
          transparency_mode = "soft";
          session_placement = "floating";
          session_position = "center";
          # Volume, brightness, network and bluetooth open the control centre under the click.
          open_near_click_control_center = true;
        };
        session = {
          show_shortcuts = true;
          # 5.3.0 has no hibernate or reboot-to-firmware action.
          actions = [
            {
              action = "lock";
              shortcut = "l";
            }
            {
              action = "suspend";
              shortcut = "s";
            }
            {
              action = "command";
              label = "Hibernate";
              glyph = "hibernate";
              command = "systemctl hibernate";
              shortcut = "h";
            }
            {
              action = "reboot";
              shortcut = "r";
            }
            {
              action = "logout";
              shortcut = "e";
            }
            {
              action = "shutdown";
              shortcut = "p";
              variant = "destructive";
            }
            {
              action = "command";
              label = "Reboot to UEFI";
              glyph = "cpu";
              command = "systemctl reboot --firmware-setup";
              shortcut = "u";
            }
          ];
        };
      };

      audio.enable_sounds = false;
      osd.position = "top_right";
      nightlight.enabled = true;
      location = {
        address = "Eindhoven";
        auto_locate = false;
      };

      wallpaper = {
        directory = wallpapers.directory;
        # Inside `directory`, so the picker shows it selected; stylix's image is a themed store copy.
        default.path = lib.mkForce wallpapers.defaultWallpaper;
      };
    };
  };

  systemd.user.services.noctalia.Service = {
    Slice = "session.slice";
    RestartSec = 2;
    # The launcher and plugins open terminals via $TERMINAL (binary only, no -e).
    Environment = ["TERMINAL=${config.cosmos.cli.terminals.defaultStandalone}"];
  };

  cosmos.system.impermanence.persist.directories = [".local/state/noctalia"];

  # GUI and IPC changes go to settings.toml, which overrides config.toml. Dropping it
  # on every activation (switch and boot) keeps nix authoritative.
  home.activation.noctaliaResetOverrides = lib.hm.dag.entryAfter ["writeBoundary"] ''
    run rm -f ${lib.escapeShellArg "${config.xdg.stateHome}/noctalia/settings.toml"}
  '';
}
