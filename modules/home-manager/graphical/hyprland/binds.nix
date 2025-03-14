{
  config,
  lib,
  ...
}: let
  programName = program: builtins.elemAt (lib.strings.splitString " " program) 0;
  toggle = program: "pkill ${programName program} || uwsm app -- ${program}";
  runOnce = program: "pgrep ${programName program} || uwsm app -- ${program}";
in {
  wayland.windowManager.hyprland.settings = {
    "$mod" = "SUPER";
    "$terminal" = "${config.modules.terminal.default}";

    bindm = [
      "$mod      , mouse:272, movewindow"
      "$mod      , mouse:273, resizewindow"
      "$mod SHIFT, mouse:272, resizewindow"
    ];

    bind = with config.modules.graphical.commands; [
      # Compositor settings
      "$mod SHIFT, Q, exec, pkill Hyprland"
      "$mod SHIFT, C, killactive"
      "$mod      , F, fullscreen"
      "$mod      , T, togglefloating"

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

      # Switch workspaces
      "$mod      , code:10, workspace, 1"
      "$mod SHIFT, code:10, movetoworkspacesilent, 1"
      "$mod      , code:11, workspace, 2"
      "$mod SHIFT, code:11, movetoworkspacesilent, 2"
      "$mod      , code:12, workspace, 3"
      "$mod SHIFT, code:12, movetoworkspacesilent, 3"
      "$mod      , code:13, workspace, 4"
      "$mod SHIFT, code:13, movetoworkspacesilent, 4"
      "$mod      , code:14, workspace, 5"
      "$mod SHIFT, code:14, movetoworkspacesilent, 5"

      # Utilities
      "$mod SHIFT, Return, exec, uwsm app -- $terminal"
      "$mod      , Tab   , exec, uwsm app -- ${toggle launcher}"
      "$mod      , Period, exec, uwsm app -- ${toggle emoji}"
      "$mod      , K     , exec, uwsm app -- ${toggle calculator}"
      "ALT       , Tab   , exec, uwsm app -- ${toggle windowSwitch}"
      "$mod SHIFT, P     , exec, uwsp app -- ${toggle passwordManager}"

      # Applications
      "$mod SHIFT, F, exec, uwsm app -- firefox"
      "$mod SHIFT, S, exec, uwsm app -- $terminal --title 'Spotify Player' -e spotify_player"
      "$mod SHIFT, D, exec, uwsm app -- discord"
    ];
  };
}
