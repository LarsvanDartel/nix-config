{
  config,
  lib,
  ...
}: let
  inherit (lib.options) mkEnableOption mkOption;
  inherit (lib.attrsets) attrNames;
  inherit (lib.types) enum;

  types = {
    default = {
      bezier = [
        "linear, 0, 0, 1, 1"
        "liner, 1, 1, 1, 1"
        "md3_standard, 0.2, 0, 0, 1"
        "md3_decel, 0.05, 0.7, 0.1, 1"
        "md3_accel, 0.3, 0, 0.8, 0.15"
        "overshot, 0.05, 0.9, 0.1, 1.1"
        "crazyshot, 0.1, 1.5, 0.76, 0.92"
        "hyprnostretch, 0.05, 0.9, 0.1, 1.0"
        "menu_decel, 0.1, 1, 0, 1"
        "menu_accel, 0.38, 0.04, 1, 0.07"
        "easeInOutCirc, 0.85, 0, 0.15, 1"
        "easeOutCirc, 0, 0.55, 0.45, 1"
        "easeOutExpo, 0.16, 1, 0.3, 1"
        "softAcDecel, 0.26, 0.26, 0.15, 1"
        "md2, 0.4, 0, 0.2, 1"
      ];
      animation = [
        "windows, 1, 3, md3_decel, popin 60%"
        "windowsIn, 1, 3, md3_decel, popin 60%"
        "windowsOut, 1, 3, md3_accel, popin 60%"
        "border, 1, 10, default"
        "borderangle, 1, 15, liner, loop"
        "fade, 1, 3, md3_decel"
        "layers, 1, 2, md3_decel, slide"
        "layersIn, 1, 3, menu_decel, slide"
        "layersOut, 1, 1.6, menu_accel"
        "fadeLayersIn, 1, 2, menu_decel"
        "fadeLayersOut, 1, 4.5, menu_accel"
        "workspaces, 1, 7, menu_decel, slide"
        "workspaces, 1, 2.5, softAcDecel, slide"
        "workspaces, 1, 7, menu_decel, slidefade 15%"
        "specialWorkspace, 1, 3, md3_decel, slidefadevert 15%"
        "specialWorkspace, 1, 3, md3_decel, slidevert"
      ];
    };
    minimal = {
      bezier = [
        "wind, 0.05, 0.9, 0.1, 1.05"
        "winIn, 0.1, 1.1, 0.1, 1.1"
        "winOut, 0.3, -0.3, 0, 1"
        "liner, 1, 1, 1, 1"
      ];

      animation = [
        "windows, 1, 6, wind, slide"
        "windowsIn, 1, 6, winIn, slide"
        "windowsOut, 1, 5, winOut, slide"
        "windowsMove, 1, 5, wind, slide"
        "border, 1, 1, liner"
        "borderangle, 1, 15, liner, loop"
        "fade, 1, 10, default"
        "workspaces, 1, 5, wind"
      ];
    };
    optimized = {
      bezier = [
        "wind, 0.05, 0.85, 0.03, 0.97"
        "winIn, 0.07, 0.88, 0.04, 0.99"
        "winOut, 0.20, -0.15, 0, 1"
        "liner, 1, 1, 1, 1"
        "md3_standard, 0.12, 0, 0, 1"
        "md3_decel, 0.05, 0.80, 0.10, 0.97"
        "md3_accel, 0.20, 0, 0.80, 0.08"
        "overshot, 0.05, 0.85, 0.07, 1.04"
        "crazyshot, 0.1, 1.22, 0.68, 0.98"
        "hyprnostretch, 0.05, 0.82, 0.03, 0.94"
        "menu_decel, 0.05, 0.82, 0, 1"
        "menu_accel, 0.20, 0, 0.82, 0.10"
        "easeInOutCirc, 0.75, 0, 0.15, 1"
        "easeOutCirc, 0, 0.48, 0.38, 1"
        "easeOutExpo, 0.10, 0.94, 0.23, 0.98"
        "softAcDecel, 0.20, 0.20, 0.15, 1"
        "md2, 0.30, 0, 0.15, 1"
        "OutBack, 0.28, 1.40, 0.58, 1"
        "easeInOutCirc, 0.78, 0, 0.15, 1"
      ];
      animation = [
        "border, 1, 1.6, liner"
        "borderangle, 1, 82, liner, once"
        "windowsIn, 1, 3.2, winIn, slide"
        "windowsOut, 1, 2.8, easeOutCirc"
        "windowsMove, 1, 3.0, wind, slide"
        "fade, 1, 1.8, md3_decel"
        "layersIn, 1, 1.8, menu_decel, slide"
        "layersOut, 1, 1.5, menu_accel"
        "fadeLayersIn, 1, 1.6, menu_decel"
        "fadeLayersOut, 1, 1.8, menu_accel"
        "workspaces, 1, 4.0, menu_decel, slide"
        "specialWorkspace, 1, 2.3, md3_decel, slidefadevert 15%"
      ];
    };
    fast = {
      bezier = [
        "linear, 0, 0, 1, 1"
        "liner, 1, 1, 1, 1"
        "md3_standard, 0.2, 0, 0, 1"
        "md3_decel, 0.05, 0.7, 0.1, 1"
        "md3_accel, 0.3, 0, 0.8, 0.15"
        "overshot, 0.05, 0.9, 0.1, 1.1"
        "crazyshot, 0.1, 1.5, 0.76, 0.92"
        "hyprnostretch, 0.05, 0.9, 0.1, 1.0"
        "fluent_decel, 0.1, 1, 0, 1"
        "easeInOutCirc, 0.85, 0, 0.15, 1"
        "easeOutCirc, 0, 0.55, 0.45, 1"
        "easeOutExpo, 0.16, 1, 0.3, 1"
      ];
      animation = [
        "windows, 1, 3, md3_decel, popin 60%"
        "border, 1, 10, default"
        "borderangle, 1, 15, liner, loop"
        "fade, 1, 2.5, md3_decel"
        "workspaces, 1, 3.5, easeOutExpo, slide"
        "specialWorkspace, 1, 3, md3_decel, slidevert"
      ];
    };
    standard = {
      bezier = "myBezier, 0.05, 0.9, 0.1, 1.05";
      animation = [
        "windows, 1, 7, myBezier"
        "windowsOut, 1, 7, default, popin 80%"
        "border, 1, 10, default"
        "borderangle, 1, 8, default, loop"
        "fade, 1, 7, default"
        "workspaces, 1, 6, default"
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
    wayland.windowManager.hyprland.settings.animations =
      {
        enabled = cfg.enable;
      }
      // types.${cfg.type};
  };
}
