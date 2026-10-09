# home.hyprland.rofi — application launcher / menu.
{...}: {
  den.aspects.home.hyprland.rofi.homeManager = {
    config,
    lib,
    pkgs,
    ...
  }: let
    inherit (lib.modules) mkForce;
    rofi-dir = ".local/share/rofi";
  in {
    cosmos.system.impermanence.persist.directories = [rofi-dir];

    # Own theme/font below; stylix's rofi target would fight it.
    stylix.targets.rofi.enable = false;

    home.packages = with pkgs; [
      jq
      rofi-systemd
      rofi-power-menu
    ];

    programs.rofi = {
      enable = true;
      plugins = with pkgs; [
        rofi-emoji
        rofi-calc
        rofi-power-menu
        rofi-systemd
      ];
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
            ${builtins.readFile ./rofi-theme.rasi}
          ''
      );
      # Not the top-level options: renamed in HM 2026-09-18, fatal under abort-on-warn.
      settings = {
        terminal = "${config.cosmos.cli.terminals.default}";
        cycle = true;
        location = 0; # center, per home-manager's former locationsMap
        cache-dir = "~/${rofi-dir}";
        show-icons = true;
        sort = true;
        kb-cancel = "Escape,Super+Shift+C";
        modi = "window,run,ssh,emoji,calc,drun,power-menu:rofi-power-menu";
      };
    };
  };
}
