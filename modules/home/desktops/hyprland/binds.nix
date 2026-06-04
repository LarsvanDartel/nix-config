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

  mod = "SUPER";
  terminal = config.cosmos.cli.terminals.default;

  programName = program: get-file-name-without-extension (builtins.elemAt (splitString " " program) 0);
  toggle = program: "pkill ${programName program} || uwsm app -- ${program}";

  exec = cmd: ''hl.dsp.exec_cmd("${cmd}")'';

  bind = key: dispatcher: ''hl.bind("${key}", ${dispatcher})'';
  bindOpts = key: dispatcher: opts: ''hl.bind("${key}", ${dispatcher}, ${opts})'';

  launcher = "rofi -show drun";
  windowSwitch = "rofi -show window";
  calculator = "rofi -show calc";
  emoji = "rofi -show emoji";
  powerMenu = "rofi -show power-menu";
  systemd = "${pkgs.rofi-systemd}/bin/rofi-systemd";
  clipse = "${terminal} -a clipse -e ${pkgs.clipse}/bin/clipse";

  workspaceBinds = flatten (
    map (i: let
      code = toString (i + 9);
      workspace = toString i;
    in [
      (bind "${mod} + SHIFT + code:${code}" "hl.dsp.window.move({workspace = ${workspace}, silent = true})")
      (bind "${mod} + code:${code}" "hl.dsp.focus({workspace = ${workspace}})")
    ])
    (range 1 9)
  );
in {
  config = mkIf cfg.enable {
    wayland.windowManager.hyprland.extraConfig =
      lib.concatStringsSep "\n" (
        [
          # Compositor
          (bind "${mod} + SHIFT + Q" (exec "pkill Hyprland"))
          (bind "${mod} + SHIFT + C" "hl.dsp.window.close()")
          (bind "${mod} + F" "hl.dsp.window.fullscreen()")
          (bind "${mod} + T" "hl.dsp.window.float({action = 'toggle'})")
          (bind "${mod} + D" "hl.dsp.window.toggle_swallow()")

          # Move focus
          (bind "${mod} + L" "hl.dsp.focus({direction = 'right'})")
          (bind "${mod} + H" "hl.dsp.focus({direction = 'left'})")
          (bind "${mod} + K" "hl.dsp.focus({direction = 'up'})")
          (bind "${mod} + J" "hl.dsp.focus({direction = 'down'})")

          # Move window
          (bind "${mod} + SHIFT + L" "hl.dsp.window.move({direction = 'right'})")
          (bind "${mod} + SHIFT + H" "hl.dsp.window.move({direction = 'left'})")
          (bind "${mod} + SHIFT + K" "hl.dsp.window.move({direction = 'up'})")
          (bind "${mod} + SHIFT + J" "hl.dsp.window.move({direction = 'down'})")

          # Resize window
          (bind "${mod} + CTRL + L" "hl.dsp.window.resize({x = 10, y = 0})")
          (bind "${mod} + CTRL + H" "hl.dsp.window.resize({x = -10, y = 0})")
          (bind "${mod} + CTRL + K" "hl.dsp.window.resize({x = 0, y = -10})")
          (bind "${mod} + CTRL + J" "hl.dsp.window.resize({x = 0, y = 10})")

          # Power menu
          (bind "${mod} + Escape" (exec "uwsm app -- ${toggle powerMenu}"))
          (bind "${mod} + SHIFT + Escape" (exec "hyprlock"))

          # Utilities
          (bind "${mod} + SHIFT + Return" (exec "uwsm app -- ${terminal}"))
          (bind "${mod} + Tab" (exec "uwsm app -- ${toggle launcher}"))
          (bind "ALT + Tab" (exec "uwsm app -- ${toggle windowSwitch}"))
          (bind "ALT + SHIFT + Return" (exec "uwsm app -- ${toggle calculator}"))
          (bind "${mod} + Period" (exec "uwsm app -- ${toggle emoji}"))
          (bind "${mod} + SHIFT + D" (exec "uwsm app -- ${toggle systemd}"))
          (bind "${mod} + V" (exec "uwsm app -- ${clipse}"))
          (bind "${mod} + S" (exec "${getExe config.programs.hyprshot.package} -m region"))
          (bind "${mod} + SHIFT + S" (exec "${getExe config.programs.hyprshot.package} -m window"))

          # Brightness
          (bindOpts "XF86MonBrightnessUp" (exec "${pkgs.brightnessctl}/bin/brightnessctl set +5%") "{locked = true, repeating = true}")
          (bindOpts "XF86MonBrightnessDown" (exec "${pkgs.brightnessctl}/bin/brightnessctl set 5%-") "{locked = true, repeating = true}")

          # Audio
          (bindOpts "XF86AudioRaiseVolume" (exec "${pkgs.pamixer}/bin/pamixer -i 5") "{locked = true, repeating = true}")
          (bindOpts "XF86AudioLowerVolume" (exec "${pkgs.pamixer}/bin/pamixer -d 5") "{locked = true, repeating = true}")
          (bindOpts "XF86AudioMute" (exec "${pkgs.pamixer}/bin/pamixer --toggle-mute") "{locked = true}")
          (bindOpts "XF86AudioMicMute" (exec "${pkgs.pamixer}/bin/pamixer --default-source --toggle-mute") "{locked = true}")

          # Media
          (bindOpts "XF86AudioNext" (exec "playerctl next") "{locked = true}")
          (bindOpts "XF86AudioPrev" (exec "playerctl previous") "{locked = true}")
          (bindOpts "XF86AudioPlay" (exec "playerctl play-pause") "{locked = true}")
          (bindOpts "XF86AudioStop" (exec "playerctl stop") "{locked = true}")

          # Mouse
          (bindOpts "${mod} + mouse:272" "hl.dsp.window.drag()" "{mouse = true}")
          (bindOpts "${mod} + mouse:273" "hl.dsp.window.resize()" "{mouse = true}")
          (bindOpts "${mod} + SHIFT + mouse:272" "hl.dsp.window.resize()" "{mouse = true}")
        ]
        ++ workspaceBinds
      )
      + "\n";
  };
}
