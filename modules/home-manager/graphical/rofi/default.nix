{
  config,
  lib,
  pkgs,
  ...
}: let
  cfg = config.modules.graphical.rofi;
  rofi-dir = ".local/share/rofi";
in {
  imports = [
    ./rofi-rbw.nix
  ];

  options.modules.graphical.rofi = {
    enable = lib.mkEnableOption "rofi";
  };

  config = lib.mkIf cfg.enable {
    modules.persist.directories = [rofi-dir];

    home.packages = with pkgs; [
      jq
      rofi-systemd
      rofi-power-menu
    ];

    programs.rofi = {
      enable = true;
      package = pkgs.rofi-wayland;
      terminal = "${config.modules.terminal.default}";
      cycle = true;
      plugins = with pkgs; [
        rofi-emoji
        rofi-calc
        rofi-power-menu
        rofi-systemd
      ];
      location = "center";
      theme = lib.mkForce (
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

    modules.graphical.commands = {
      launcher = "rofi -show drun";
      windowSwitch = "rofi -show window";
      calculator = "rofi -show calc";
      emoji = "rofi -show emoji";
      powerMenu = "rofi -show power-menu";
    };
  };
}
