{
  config,
  lib,
  pkgs,
  ...
}: let
  cfg = config.modules.graphical.mako;
in {
  options.modules.graphical.mako = {
    enable = lib.mkEnableOption "mako";
  };

  config = lib.mkIf cfg.enable {
    modules.graphical.startupCommands = lib.mkOrder 800 [
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
