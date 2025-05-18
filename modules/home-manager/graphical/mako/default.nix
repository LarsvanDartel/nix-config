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
        defaultTimeout = 5000;
        anchor = "top-right";
        borderSize = 3;
        borderRadius = 7;
        border-color = {
          "urgency=low" = base0B;
          "urgency=normal" = base0C;
          "urgency=high" = base08;
        };
        backgroundColor = "${base00}10";
        padding = "20";
        margin = "30";
        sort = "-time";
        format = "<b>%s</b>\\n<span color=\"${base03}\">(%a)</span>\\n%b";
      };
    };
  };
}
