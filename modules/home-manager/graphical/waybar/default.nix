{
  config,
  lib,
  pkgs,
  ...
}: let
  cfg = config.modules.graphical.waybar;
  terminal = config.modules.terminal.default;
in {
  options.modules.graphical.waybar = {
    enable = lib.mkEnableOption "waybar";
  };

  config = lib.mkIf cfg.enable {
    stylix.targets.waybar.enable = false;
    programs.waybar = {
      enable = true;
      systemd.enable = true;
      style = with config.lib.stylix.colors.withHashtag;
        ''
          @define-color base00 ${base00}; @define-color base01 ${base01};
          @define-color base02 ${base02}; @define-color base03 ${base03};
          @define-color base04 ${base04}; @define-color base05 ${base05};
          @define-color base06 ${base06}; @define-color base07 ${base07};
          @define-color base08 ${base08}; @define-color base09 ${base09};
          @define-color base0A ${base0A}; @define-color base0B ${base0B};
          @define-color base0C ${base0C}; @define-color base0D ${base0D};
          @define-color base0E ${base0E}; @define-color base0F ${base0F};
        ''
        + builtins.readFile ./style.css;
      settings = with config.modules.graphical.commands; [
        {
          layer = "top";
          height = 20;
          spacing = 5;
          margin-top = 5;
          margin-left = 20;
          margin-right = 20;
          margin-down = 0;
          modules-left = ["group/hardware"];
          modules-center = ["hyprland/workspaces"];
          modules-right = ["tray" "custom/cliphist" "group/right"];
          "group/hardware" = {
            orientation = "horizontal";
            modules = [
              "cpu"
              "memory"
              "backlight"
              "pulseaudio"
              "network"
              "bluetooth"
            ];
          };
          "network" = {
            interface = "wlp0*";
            format-wifi = "󰤨  {essid}";
            format-ethernet = "󰈀 {ipaddr}/{cidr}";
            tooltip-format = "{essid}: {ifname} via 󰩟 {ipaddr}\n\nClick to open nmtui.";
            format-linked = "{essid} {ifname} (No IP) 󰩟";
            format-disconnected = "󰤭 ";
            on-click = "${terminal} -e ${pkgs.networkmanager}/bin/nmtui";
          };
          "cpu" = {
            interval = 10;
            format = "   {usage:d}%";
            max-length = 10;
            on-click = "${terminal} -e btop";
          };
          "memory" = {
            interval = 10;
            format = "   {percentage}%";
            tooltip-format = "{used:0.1f}GiB used\n\nClick to open btop.";
            on-click = "${terminal} -e ${pkgs.btop}/bin/btop";
          };
          "backlight" = {
            format = "{icon}  {percent}%";
            format-icons = ["󰃞" "󰃟" "󰖨"];
            tooltip-format = "Backlight at {percent}%\n\nScroll to change brightness.";
          };
          "pulseaudio" = {
            format = "{icon} {volume}%";
            # format-alt = "{format_source}";
            # format = "{icon} {volume}% {format_source}";
            format-bluetooth = "{volume}% 󰥰 {format_source}";
            format-bluetooth-muted = "󰟎 {format_source}";
            format-muted = "󰝟 {format_source}";
            format-source = "󰍬 {volume}%";
            format-source-muted = "󰍭";
            on-click = "${terminal} -e ${pkgs.pulsemixer}/bin/pulsemixer";
            tooltip-format = "{desc}\n\nClick to open pulsemixer, scroll to change volume.";
            "format-icons" = {
              headphone = "󰋋";
              hands-free = "󰋋";
              headset = "󰋋";
              phone = "";
              portable = "";
              car = "";
              muted-icon = "󰝟";
              default = ["󰕿" "󰖀" "󰕾"];
            };
          };
          "bluetooth" = {
            format = "";
            format-connected = " {num_connections}";
            format-disabled = " DISABLED";
            format-off = " OFF";
            interval = 30;
            on-click = "${terminal} -e ${pkgs.bluetuith}/bin/bluetuith";
            format-no-controller = "";
            tooltip-format = "{num_connections} devices are currently connected to '{controller_alias}'.\n\nClick to open bluetuith.";
            tooltip-format-connected = "Controller '{controller_alias}' has the following {num_connections} devices connected:\n\n{device_enumerate}";
            tooltip-format-enumerate-connected = "{device_alias} ({device_address})";
            tooltip-format-enumerate-connected-battery = "{device_alias} ({device_address}) {device_battery_percentage}% battery";
          };
          "hyprland/workspaces" = {
            persistent-workspaces = [1 2 3 4 5 6 7 8 9];
          };
          "tray" = {
            spacing = 10;
            icon-size = 24;
            show-passive-items = true;
          };
          "group/right" = {
            orientation = "horizontal";
            modules = [
              "battery"
              "clock"
              "custom/exit"
            ];
          };
          "custom/cliphist" = {
            format = "";
            on-click = "sleep 0.1 && ${config.home.homeDirectory}/cliphist-helper.sh open";
            on-click-middle = "sleep 0.1 && ${config.home.homeDirectory}/cliphist-helper.sh wipe";
            on-click-right = "sleep 0.1 && ${config.home.homeDirectory}/cliphist-helper.sh remove";
            tooltip-format = "Cliphist\n\n<small>Click to open and select to copy to clipboard, middle click to\nwipe entire history, and right click to open menu in order to\nremove a single item.</small>";
          };
          "battery" = {
            "states" = {
              good = 95;
              warning = 25;
              critical = 5;
            };
            bat = "BAT0";
            format = "{icon} {capacity}%";
            format-charging = "  {capacity}%";
            format-plugged = "  {capacity}%";
            format-icons = ["" "" "" "" ""];
          };
          "clock" = {
            #format = "<big>      <b>{:%H:%M</b></big>\n<small>󰃮  %d %h %Y</small>}"; # Time in row one, date in row two; suggested height = 45
            locale = "nl_NL.UTF-8";
            format = "<big><b>{:%H:%M}</b></big>";
            format-alt = "<big><b>󰃮  {:%Y-%m-%d}</b></big>";
            tooltip-format = "<big>{:%Y %B}</big>\n<tt><small>{calendar}</small></tt>";
            calendar = {
              mode = "year";
              mode-mon-col = 3;
              weeks-pos = "left";
              on-scroll = 1;
              "format" = with config.lib.stylix.colors.withHashtag; {
                months = "<span color='${base0D}'><b>{}</b></span>";
                days = "<span color='${base06}'><b>{}</b></span>";
                weeks = "<span color='${base07}'><b>W{}</b></span>";
                weekdays = "<span color='${base0F}'><b>{}</b></span>";
                today = "<span color='${base08}'><b><u>{}</u></b></span>";
              };
            };
            actions = {
              on-click-right = "mode";
              on-click-forward = "tz_up";
              on-click-backward = "tz_down";
              on-scroll-up = "shift_up";
              on-scroll-down = "shift_down";
            };
          };
          "custom/exit" = {
            format = "";
            on-click = "sleep 0.2 && ${powerMenu}";
            tooltip-format = "Power menu\n\n<small>Click to open menu.</small>";
          };
        }
      ];
    };
  };
}
