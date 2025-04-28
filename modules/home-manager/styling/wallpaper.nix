{
  config,
  pkgs,
  lib,
  ...
}: let
  inherit (builtins) readDir attrNames;
  inherit (lib.options) mkOption mkEnableOption;
  inherit (lib.types) str;
  inherit (lib.strings) optionalString splitString removeSuffix concatStringsSep;
  inherit (lib.lists) findFirst init last length;
  cfg = config.modules.styling.wallpaper;
in {
  options.modules.styling.wallpaper = {
    image = mkOption {
      type = str;
      default = "minimal/a_flower_on_a_dark_background.png";
      description = "Path to the background image in the source repository.";
    };
    themed = mkEnableOption "themed background";
    inverted = mkEnableOption "invert background";
    src = mkOption {
      default = pkgs.fetchFromGitHub {
        owner = "dharmx";
        repo = "walls";
        rev = "6bf4d733ebf2b484a37c17d742eb47e5139e6a14";
        sha256 = "sha256-M96jJy3L0a+VkJ+DcbtrRAquwDWaIG9hAUxenr/TcQU=";
      };
    };
    path = mkOption {
      type = str;
      description = "Path to the background image.";
      default = let
        theme = pkgs.writeTextFile {
          name = "gowall-theme";
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
          executable = true;
        };

        fileExtension = name: let
          parts = splitString "." name;
        in
          if length parts > 1
          then last parts
          else "";

        image = let
          parts = splitString "/" cfg.image;
          dirParts = init parts; # all but last part
          fileBase = last parts; # last part (the base filename without extension)
          dirPath = concatStringsSep "/" (["${cfg.src}"] ++ dirParts);
          entries = attrNames (readDir dirPath);
          match =
            findFirst
            (name: (removeSuffix ("." + fileExtension name) name) == fileBase)
            null
            entries;
        in
          if match != null
          then "${concatStringsSep "/" dirParts}/${match}"
          else throw "Image not found: ${cfg.image}";

        wallpaper-themed = pkgs.stdenv.mkDerivation {
          name = "wallpaper-themed-1.0.0";

          inherit (cfg) src;

          buildInputs = with pkgs; [
            gowall
            imagemagick
            (writeShellScriptBin "xdg-open" "")
          ];

          buildPhase = ''
            ${optionalString cfg.inverted ''
              convert ./${image} -channel RGB -negate ./${image}
            ''}
            ${
              if cfg.themed
              then ''
                cp ${theme} ./theme.json

                export HOME=$PWD

                gowall convert ./${image} --output ./themed.${fileExtension image} --theme ./theme.json
              ''
              else ''
                cp ${image} ./themed.${fileExtension image}
              ''
            }
            mogrify -format png themed.*
          '';

          installPhase = ''
            install -Dm644 -t $out themed.png
          '';
        };
      in "${wallpaper-themed}/themed.png";
    };
  };
}
