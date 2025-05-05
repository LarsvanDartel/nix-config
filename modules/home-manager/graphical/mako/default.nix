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

    services.mako = with config.lib.stylix.colors.withHashtag; {
      enable = true;
      settings = {
        defaultTimeout = 5000;
        anchor = "top-right";
        borderSize = 3;
        borderRadius = 7;
        backgroundColor = "${base00}10";
        padding = "20";
        margin = "30";
        sort = "-time";
        format = "<b>%s</b>\\n<span color=\"${base03}\">(%a)</span>\\n%b";
      };
      criteria = {
        "urgency=low" = {
          border-color = base0B;
        };
        "urgency=normal" = {
          border-color = base0C;
        };
        "urgency=high" = {
          border-color = base08;
        };
      };
    };
  };
}
