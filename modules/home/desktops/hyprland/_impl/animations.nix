{
  config,
  lib,
  ...
}: let
  inherit (lib.options) mkEnableOption mkOption;
  inherit (lib.attrsets) attrNames;
  inherit (lib.types) enum;

  bezier = name: x1: y1: x2: y2: {
    _args = [
      name
      {
        type = "bezier";
        points = [[x1 y1] [x2 y2]];
      }
    ];
  };

  anim = spec: {_args = [spec];};

  types = {
    default = {
      curve = [
        (bezier "linear" 0 0 1 1)
        (bezier "liner" 1 1 1 1)
        (bezier "md3_standard" 0.2 0 0 1)
        (bezier "md3_decel" 0.05 0.7 0.1 1)
        (bezier "md3_accel" 0.3 0 0.8 0.15)
        (bezier "overshot" 0.05 0.9 0.1 1.1)
        (bezier "crazyshot" 0.1 1.5 0.76 0.92)
        (bezier "hyprnostretch" 0.05 0.9 0.1 1.0)
        (bezier "menu_decel" 0.1 1 0 1)
        (bezier "menu_accel" 0.38 0.04 1 0.07)
        (bezier "easeInOutCirc" 0.85 0 0.15 1)
        (bezier "easeOutCirc" 0 0.55 0.45 1)
        (bezier "easeOutExpo" 0.16 1 0.3 1)
        (bezier "softAcDecel" 0.26 0.26 0.15 1)
        (bezier "md2" 0.4 0 0.2 1)
      ];
      animation = [
        (anim {
          leaf = "windows";
          enabled = true;
          speed = 3;
          bezier = "md3_decel";
          style = "popin 60%";
        })
        (anim {
          leaf = "windowsIn";
          enabled = true;
          speed = 3;
          bezier = "md3_decel";
          style = "popin 60%";
        })
        (anim {
          leaf = "windowsOut";
          enabled = true;
          speed = 3;
          bezier = "md3_accel";
          style = "popin 60%";
        })
        (anim {
          leaf = "border";
          enabled = true;
          speed = 10;
          bezier = "default";
        })
        (anim {
          leaf = "borderangle";
          enabled = true;
          speed = 15;
          bezier = "liner";
          style = "loop";
        })
        (anim {
          leaf = "fade";
          enabled = true;
          speed = 3;
          bezier = "md3_decel";
        })
        (anim {
          leaf = "layers";
          enabled = true;
          speed = 2;
          bezier = "md3_decel";
          style = "slide";
        })
        (anim {
          leaf = "layersIn";
          enabled = true;
          speed = 3;
          bezier = "menu_decel";
          style = "slide";
        })
        (anim {
          leaf = "layersOut";
          enabled = true;
          speed = 1.6;
          bezier = "menu_accel";
        })
        (anim {
          leaf = "fadeLayersIn";
          enabled = true;
          speed = 2;
          bezier = "menu_decel";
        })
        (anim {
          leaf = "fadeLayersOut";
          enabled = true;
          speed = 4.5;
          bezier = "menu_accel";
        })
        (anim {
          leaf = "workspaces";
          enabled = true;
          speed = 7;
          bezier = "menu_decel";
          style = "slide";
        })
        (anim {
          leaf = "workspaces";
          enabled = true;
          speed = 2.5;
          bezier = "softAcDecel";
          style = "slide";
        })
        (anim {
          leaf = "workspaces";
          enabled = true;
          speed = 7;
          bezier = "menu_decel";
          style = "slidefade 15%";
        })
        (anim {
          leaf = "specialWorkspace";
          enabled = true;
          speed = 3;
          bezier = "md3_decel";
          style = "slidefadevert 15%";
        })
        (anim {
          leaf = "specialWorkspace";
          enabled = true;
          speed = 3;
          bezier = "md3_decel";
          style = "slidevert";
        })
      ];
    };
    minimal = {
      curve = [
        (bezier "wind" 0.05 0.9 0.1 1.05)
        (bezier "winIn" 0.1 1.1 0.1 1.1)
        (bezier "winOut" 0.3 (-0.3) 0 1)
        (bezier "liner" 1 1 1 1)
      ];
      animation = [
        (anim {
          leaf = "windows";
          enabled = true;
          speed = 6;
          bezier = "wind";
          style = "slide";
        })
        (anim {
          leaf = "windowsIn";
          enabled = true;
          speed = 6;
          bezier = "winIn";
          style = "slide";
        })
        (anim {
          leaf = "windowsOut";
          enabled = true;
          speed = 5;
          bezier = "winOut";
          style = "slide";
        })
        (anim {
          leaf = "windowsMove";
          enabled = true;
          speed = 5;
          bezier = "wind";
          style = "slide";
        })
        (anim {
          leaf = "border";
          enabled = true;
          speed = 1;
          bezier = "liner";
        })
        (anim {
          leaf = "borderangle";
          enabled = true;
          speed = 15;
          bezier = "liner";
          style = "loop";
        })
        (anim {
          leaf = "fade";
          enabled = true;
          speed = 10;
          bezier = "default";
        })
        (anim {
          leaf = "workspaces";
          enabled = true;
          speed = 5;
          bezier = "wind";
        })
      ];
    };
    optimized = {
      curve = [
        (bezier "wind" 0.05 0.85 0.03 0.97)
        (bezier "winIn" 0.07 0.88 0.04 0.99)
        (bezier "winOut" 0.20 (-0.15) 0 1)
        (bezier "liner" 1 1 1 1)
        (bezier "md3_standard" 0.12 0 0 1)
        (bezier "md3_decel" 0.05 0.80 0.10 0.97)
        (bezier "md3_accel" 0.20 0 0.80 0.08)
        (bezier "overshot" 0.05 0.85 0.07 1.04)
        (bezier "crazyshot" 0.1 1.22 0.68 0.98)
        (bezier "hyprnostretch" 0.05 0.82 0.03 0.94)
        (bezier "menu_decel" 0.05 0.82 0 1)
        (bezier "menu_accel" 0.20 0 0.82 0.10)
        (bezier "easeInOutCirc" 0.75 0 0.15 1)
        (bezier "easeOutCirc" 0 0.48 0.38 1)
        (bezier "easeOutExpo" 0.10 0.94 0.23 0.98)
        (bezier "softAcDecel" 0.20 0.20 0.15 1)
        (bezier "md2" 0.30 0 0.15 1)
        (bezier "OutBack" 0.28 1.40 0.58 1)
      ];
      animation = [
        (anim {
          leaf = "border";
          enabled = true;
          speed = 1.6;
          bezier = "liner";
        })
        (anim {
          leaf = "borderangle";
          enabled = true;
          speed = 82;
          bezier = "liner";
          style = "once";
        })
        (anim {
          leaf = "windowsIn";
          enabled = true;
          speed = 3.2;
          bezier = "winIn";
          style = "slide";
        })
        (anim {
          leaf = "windowsOut";
          enabled = true;
          speed = 2.8;
          bezier = "easeOutCirc";
        })
        (anim {
          leaf = "windowsMove";
          enabled = true;
          speed = 3.0;
          bezier = "wind";
          style = "slide";
        })
        (anim {
          leaf = "fade";
          enabled = true;
          speed = 1.8;
          bezier = "md3_decel";
        })
        (anim {
          leaf = "layersIn";
          enabled = true;
          speed = 1.8;
          bezier = "menu_decel";
          style = "slide";
        })
        (anim {
          leaf = "layersOut";
          enabled = true;
          speed = 1.5;
          bezier = "menu_accel";
        })
        (anim {
          leaf = "fadeLayersIn";
          enabled = true;
          speed = 1.6;
          bezier = "menu_decel";
        })
        (anim {
          leaf = "fadeLayersOut";
          enabled = true;
          speed = 1.8;
          bezier = "menu_accel";
        })
        (anim {
          leaf = "workspaces";
          enabled = true;
          speed = 4.0;
          bezier = "menu_decel";
          style = "slide";
        })
        (anim {
          leaf = "specialWorkspace";
          enabled = true;
          speed = 2.3;
          bezier = "md3_decel";
          style = "slidefadevert 15%";
        })
      ];
    };
    fast = {
      curve = [
        (bezier "linear" 0 0 1 1)
        (bezier "liner" 1 1 1 1)
        (bezier "md3_standard" 0.2 0 0 1)
        (bezier "md3_decel" 0.05 0.7 0.1 1)
        (bezier "md3_accel" 0.3 0 0.8 0.15)
        (bezier "overshot" 0.05 0.9 0.1 1.1)
        (bezier "crazyshot" 0.1 1.5 0.76 0.92)
        (bezier "hyprnostretch" 0.05 0.9 0.1 1.0)
        (bezier "fluent_decel" 0.1 1 0 1)
        (bezier "easeInOutCirc" 0.85 0 0.15 1)
        (bezier "easeOutCirc" 0 0.55 0.45 1)
        (bezier "easeOutExpo" 0.16 1 0.3 1)
      ];
      animation = [
        (anim {
          leaf = "windows";
          enabled = true;
          speed = 3;
          bezier = "md3_decel";
          style = "popin 60%";
        })
        (anim {
          leaf = "border";
          enabled = true;
          speed = 10;
          bezier = "default";
        })
        (anim {
          leaf = "borderangle";
          enabled = true;
          speed = 15;
          bezier = "liner";
          style = "loop";
        })
        (anim {
          leaf = "fade";
          enabled = true;
          speed = 2.5;
          bezier = "md3_decel";
        })
        (anim {
          leaf = "workspaces";
          enabled = true;
          speed = 3.5;
          bezier = "easeOutExpo";
          style = "slide";
        })
        (anim {
          leaf = "specialWorkspace";
          enabled = true;
          speed = 3;
          bezier = "md3_decel";
          style = "slidevert";
        })
      ];
    };
    standard = {
      curve = [
        (bezier "myBezier" 0.05 0.9 0.1 1.05)
      ];
      animation = [
        (anim {
          leaf = "windows";
          enabled = true;
          speed = 7;
          bezier = "myBezier";
        })
        (anim {
          leaf = "windowsOut";
          enabled = true;
          speed = 7;
          bezier = "default";
          style = "popin 80%";
        })
        (anim {
          leaf = "border";
          enabled = true;
          speed = 10;
          bezier = "default";
        })
        (anim {
          leaf = "borderangle";
          enabled = true;
          speed = 8;
          bezier = "default";
          style = "loop";
        })
        (anim {
          leaf = "fade";
          enabled = true;
          speed = 7;
          bezier = "default";
        })
        (anim {
          leaf = "workspaces";
          enabled = true;
          speed = 6;
          bezier = "default";
        })
      ];
    };
  };

  cfg = config.cosmos.desktops.hyprland.animations;
in {
  options.cosmos.desktops.hyprland.animations = {
    enable = mkEnableOption "animations" // {default = true;};
    type = mkOption {
      type = enum (attrNames types);
      default = "default";
      description = "Animation type to use";
    };
  };

  config = {
    wayland.windowManager.hyprland.settings =
      {
        inherit (types.${cfg.type}) curve animation;
      }
      // {
        config.animations.enabled = cfg.enable;
      };
  };
}
