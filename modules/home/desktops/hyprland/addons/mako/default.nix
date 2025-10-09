{
  config,
  lib,
  pkgs,
  ...
}: let
  inherit (lib.options) mkEnableOption;
  inherit (lib.modules) mkIf mkOrder;

  cfg = config.desktops.hyprland.addons.mako;
in {
  options.desktops.hyprland.addons.mako = {
    enable = mkEnableOption "mako";
  };

  config = mkIf cfg.enable {
    desktops.hyprland.exec-once-extras = mkOrder 800 [
      "${pkgs.mako}/bin/mako"
    ];

    stylix.targets.mako.enable = false;

    services.mako = {
      enable = true;
      settings = with config.lib.stylix.colors.withHashtag; {
        default-timeout = 5000;
        anchor = "top-right";
        border-size = 3;
        border-radius = 7;
        "urgency=low" = {
          border-color = base0B;
        };
        "urgency=normal" = {
          border-color = base0C;
        };
        "urgency=high" = {
          border-color = base08;
        };
        background-color = "${base00}10";
        padding = "20";
        margin = "30";
        sort = "-time";
        format = "<b>%s</b>\\n<span color=\"${base03}\">(%a)</span>\\n%b";
      };
    };
  };
}
