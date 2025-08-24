{
  config,
  pkgs,
  lib,
  ...
}: let
  inherit (lib.options) mkOption mkEnableOption;
  inherit (lib.types) str;
  inherit (lib.strings) optionalString splitString;
  inherit (lib.lists) last length;

  cfg = config.styling.wallpaper;
in {
  options.styling.wallpaper = {
    themed = mkEnableOption "themed background";
    inverted = mkEnableOption "invert background";
    src = mkOption {
      default = pkgs.fetchurl {
        url = "https://raw.githubusercontent.com/dharmx/walls/6bf4d733ebf2b484a37c17d742eb47e5139e6a14/nord/a_blue_and_grey_logo.png";
        hash = "sha256-jB7q1PAMKS0tfk0Ck6pGkbsfwO+7FHwI83dUHO86ftM=";
      };
    };
    path = mkOption {
      type = str;
      description = "Path to the background image.";
      default = let
        theme = pkgs.writeTextFile {
          name = "gowall-theme.json";
          text = builtins.toJSON {
            name = "NixOS";
            colors = with config.lib.stylix.colors.withHashtag; [
              base00
              base01
              base02
              base03
              base04
              base05
              base06
              base07
              base08
              base09
              base0A
              base0B
              base0C
              base0D
              base0E
              base0F
            ];
          };
        };

        fileName = name: let
          parts = splitString "/" name;
        in
          if length parts > 1
          then last parts
          else name;

        image = fileName cfg.src;

        wallpaper-themed = pkgs.stdenv.mkDerivation {
          name = "wallpaper-themed-1.0.0";

          inherit (cfg) src;

          buildInputs = with pkgs; [
            gowall
            (writeShellScriptBin "xdg-open" "")
          ];

          unpackPhase = ''
            cp ${cfg.src} ${image}
            chmod u+w ${image}
          '';

          buildPhase = ''
            export HOME=$PWD
            ${optionalString cfg.inverted "gowall invert ${image} --output ${image}"}
            gowall convert ${image} --output wallpaper.png ${optionalString cfg.themed "-t ${theme}"}
          '';

          installPhase = ''
            install -Dm644 -t $out wallpaper.png
          '';
        };
      in "${wallpaper-themed}/wallpaper.png";
    };
  };

  config = {
    stylix.image = cfg.path;
  };
}
