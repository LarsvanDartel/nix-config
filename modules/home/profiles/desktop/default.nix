{
  config,
  lib,
  pkgs,
  ...
}: let
  inherit (lib.options) mkEnableOption;
  inherit (lib.modules) mkIf;

  cfg = config.cosmos.profiles.desktop;
in {
  options.cosmos.profiles.desktop = {
    enable = mkEnableOption "desktop configuration";
  };

  config = mkIf cfg.enable {
    cosmos = {
      profiles = {
        common.enable = true;
      };

      desktops.common = {
        styling = {
          enable = true;

          fonts = let
            fontpkgs = config.cosmos.desktops.common.styling.fonts.pkgs;
          in {
            enable = true;
            serif = fontpkgs."DejaVu Serif";
            sansSerif = fontpkgs."DejaVu Sans";
            monospace = fontpkgs."Cozette";
            emoji = fontpkgs."Noto Color Emoji";
            interface = fontpkgs."Cozette";
            extraFonts = [];
          };

          theme.nord = {
            enable = true;
            darkMode = true;
          };

          wallpaper = {
            src = pkgs.fetchurl {
              url = "https://raw.githubusercontent.com/dharmx/walls/6bf4d733ebf2b484a37c17d742eb47e5139e6a14/digital/a_group_of_birds_flying_in_the_sky.jpg";
              hash = "sha256-v6KVInk5JJZPLkOAfC8yuDQtnZtT1DWQI7u6UfG59WY=";
            };
            themed = true;
          };
        };
      };

      browsers.firefox.enable = true;

      cli = {
        terminals.foot.enable = true;
        programs = {
          bluetuith.enable = true;
          pulsemixer.enable = true;
        };
      };

      media = {
        mpv.enable = true;
        spotify.enable = true;
      };

      services = {
        kde-connect.enable = true;
      };

      social = {
        discord.enable = true;
        signal.enable = true;
      };
    };
  };
}
