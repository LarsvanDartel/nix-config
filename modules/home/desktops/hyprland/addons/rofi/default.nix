{
  config,
  lib,
  pkgs,
  ...
}: let
  inherit (lib.options) mkEnableOption mkPackageOption;
  inherit (lib.modules) mkIf mkForce;

  cfg = config.desktops.hyprland.addons.rofi;
  rofi-dir = ".local/share/rofi";
in {
  options.desktops.hyprland.addons.rofi = {
    enable = mkEnableOption "rofi";
    package = mkPackageOption pkgs "rofi" {};
  };

  config = mkIf cfg.enable {
    system.impermanence.persist.directories = [rofi-dir];

    home.packages = with pkgs; [
      jq
      rofi-systemd
      rofi-power-menu
    ];

    programs.rofi = {
      enable = true;
      inherit (cfg) package;
      terminal = "${config.cli.terminals.default}";
      cycle = true;
      plugins = with pkgs; [
        rofi-emoji
        rofi-calc
        rofi-power-menu
        rofi-systemd
      ];
      location = "center";
      theme = mkForce (
        with config.lib.stylix.colors.withHashtag;
          builtins.toFile "theme.rasi" ''
            * {
              font:             "JetBrains Mono Regular 12";
              bg0:              ${base00}10;
              bg1:              ${base02};
              fg0:              ${base03};
              fg1:              ${base0D};
              fg2:              ${base0A};
              fg3:              ${base02};
              regular-color:    ${base06};
              dark-color:       ${base00};
              accent-color:     ${base0F};
              select-color:     ${base0A};
              background-color: transparent;
              background:       transparent;
              text-color:       ${base06};
            }
            ${builtins.readFile ./theme.rasi}
          ''
      );
      extraConfig = {
        cache-dir = "~/${rofi-dir}";
        show-icons = true;
        sort = true;
        kb-cancel = "Escape,Super+Shift+C";
        modi = "window,run,ssh,emoji,calc,drun,power-menu:rofi-power-menu";
      };
    };
  };
}
