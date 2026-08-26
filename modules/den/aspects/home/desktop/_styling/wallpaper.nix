{
  config,
  inputs,
  pkgs,
  lib,
  ...
}: let
  inherit (lib.options) mkOption mkEnableOption;
  inherit (lib.types) str;
  inherit (lib.strings) optionalString splitString;
  inherit (lib.lists) last length;
  inherit (lib.modules) mkIf;

  cfg = config.cosmos.desktops.common.styling.wallpaper;
in {
  options.cosmos.desktops.common.styling.wallpaper = {
    themed = mkEnableOption "themed background";
    inverted = mkEnableOption "invert background";
    # The image `stylix.image` derives the whole colour scheme from — so this
    # one is not interchangeable with the backgrounds in the picker, and it
    # lives in the repo's `defaults/` under a name that says as much.
    src = mkOption {
      default = "${inputs.wallpapers}/defaults/stylix-source-logo.png";
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

  config = mkIf config.cosmos.desktops.common.styling.enable {
    stylix.image = cfg.path;
  };
}
