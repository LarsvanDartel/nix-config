{
  config,
  lib,
  pkgs,
  ...
}: let
  inherit (lib.cosmos) get-file-name-without-extension;
  inherit (lib.lists) flatten range;
  inherit (lib.strings) splitString;
  inherit (lib.modules) mkIf;
  inherit (lib.meta) getExe;

  cfg = config.cosmos.desktops.hyprland;

  programName = program: get-file-name-without-extension (builtins.elemAt (splitString " " program) 0);
  toggle = program: "pkill ${programName program} || uwsm app -- ${program}";
  # runOnce = program: "pgrep ${programName program} || uwsm app -- ${program}";
in {
  config = mkIf cfg.enable {
    wayland.windowManager.hyprland.settings = {
      "$mod" = "SUPER";
      "$terminal" = "${config.cosmos.cli.terminals.default}";

      bind = let
        launcher = "rofi -show drun";
        windowSwitch = "rofi -show window";
        calculator = "rofi -show calc";
        emoji = "rofi -show emoji";
        powerMenu = "rofi -show power-menu";
        systemd = "${pkgs.rofi-systemd}/bin/rofi-systemd";
        clipse = "$terminal -a clipse -e ${pkgs.clipse}/bin/clipse";

        workspaceBinds = flatten (
          map (i: let
            code = toString (i + 9);
            workspace = toString i;
          in [
            "$mod SHIFT, code:${code}, movetoworkspacesilent, ${workspace}"
            "$mod      , code:${code}, workspace, ${workspace}"
          ])
          (range 1 9)
        );
      in
        [
          # Compositor settings
          "$mod SHIFT, Q, exec, pkill Hyprland"
          "$mod SHIFT, C, killactive"
          "$mod      , F, fullscreen"
          "$mod      , T, togglefloating"
          "$mod      , D, toggleswallow"

          # Move/resize window
          "$mod      , L, movefocus, r"
          "$mod      , H, movefocus, l"
          "$mod      , K, movefocus, u"
          "$mod      , J, movefocus, d"
          "$mod SHIFT, L, movewindow, r"
          "$mod SHIFT, H, movewindow, l"
          "$mod SHIFT, K, movewindow, u"
          "$mod SHIFT, J, movewindow, d"
          "$mod CTRL , L, resizeactive, 10 0"
          "$mod CTRL , H, resizeactive, -10 0"
          "$mod CTRL , K, resizeactive, 0 -10"
          "$mod CTRL , J, resizeactive, 0 10"

          # Power menu
          "$mod      , Escape, exec, uwsm app -- ${toggle powerMenu}"
          "$mod SHIFT, Escape, exec, hyprlock"

          # Utilities
          "$mod SHIFT, Return, exec, uwsm app -- $terminal"
          "$mod      , Tab   , exec, uwsm app -- ${toggle launcher}"
          "ALT       , Tab   , exec, uwsm app -- ${toggle windowSwitch}"
          "ALT SHIFT , Return, exec, uwsm app -- ${toggle calculator}"
          "$mod      , Period, exec, uwsm app -- ${toggle emoji}"
          "$mod SHIFT, D     , exec, uwsm app -- ${toggle systemd}"
          "$mod      , V     , exec, uwsm app -- ${clipse}"
          "$mod      , S     , exec, ${getExe config.programs.hyprshot.package} -m region"
          "$mod SHIFT, S     , exec, ${getExe config.programs.hyprshot.package} -m window"
        ]
        ++ workspaceBinds;

      bindi = [
        ",XF86MonBrightnessUp, exec, ${pkgs.brightnessctl}/bin/brightnessctl set +5%"
        ",XF86MonBrightnessDown, exec, ${pkgs.brightnessctl}/bin/brightnessctl set 5%-"
        ",XF86AudioRaiseVolume, exec, ${pkgs.pamixer}/bin/pamixer -i 5"
        ",XF86AudioLowerVolume, exec, ${pkgs.pamixer}/bin/pamixer -d 5"
        ",XF86AudioMute, exec, ${pkgs.pamixer}/bin/pamixer --toggle-mute"
        ",XF86AudioMicMute, exec, ${pkgs.pamixer}/bin/pamixer --default-source --toggle-mute"
        ",XF86AudioNext, exec,playerctl next"
        ",XF86AudioPrev, exec,playerctl previous"
        ",XF86AudioPlay, exec,playerctl play-pause"
        ",XF86AudioStop, exec,playerctl stop"
      ];

      bindm = [
        "$mod      , mouse:272, movewindow"
        "$mod      , mouse:273, resizewindow"
        "$mod SHIFT, mouse:272, resizewindow"
      ];
    };
  };
}
