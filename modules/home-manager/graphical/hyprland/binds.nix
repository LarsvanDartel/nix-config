{
  config,
  lib,
  ...
}: let
  inherit (lib.lists) flatten range;

  programName = program: builtins.elemAt (lib.strings.splitString " " program) 0;
  toggle = program: "pkill ${programName program} || uwsm app -- ${program}";
  runOnce = program: "pgrep ${programName program} || uwsm app -- ${program}";
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
in {
  wayland.windowManager.hyprland.settings = {
    "$mod" = "SUPER";
    "$terminal" = "${config.modules.terminal.default}";

    bindm = [
      "$mod      , mouse:272, movewindow"
      "$mod      , mouse:273, resizewindow"
      "$mod SHIFT, mouse:272, resizewindow"
    ];

    bind = with config.modules.graphical.commands;
      [
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

        # Power menu
        "$mod      , Escape, exec, uwsm app -- ${toggle powerMenu}"

        # Utilities
        "$mod SHIFT, Return, exec, uwsm app -- $terminal"
        "$mod      , Tab   , exec, uwsm app -- ${toggle launcher}"
        "$mod      , Period, exec, uwsm app -- ${toggle emoji}"
        "ALT       , Tab   , exec, uwsm app -- ${toggle windowSwitch}"
        "$mod SHIFT, P     , exec, uwsp app -- ${toggle passwordManager}"

        # Applications
        "$mod SHIFT, F, exec, uwsm app -- firefox"
        "$mod SHIFT, D, exec, uwsm app -- discord"
      ]
      ++ workspaceBinds;
  };
}
