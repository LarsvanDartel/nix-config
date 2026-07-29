# home.wallpapers — a small set of default backgrounds, recoloured to the active
# stylix palette and linked into a directory the wallpaper picker (noctalia's
# WallpaperSelector / control centre) browses.
#
# The images are run through imagemagick's `-remap` against a swatch strip built
# from the 16 base16 colours, with Floyd–Steinberg dithering. The result uses
# *only* theme colours, so every background matches the bar, terminal and app
# theming instead of clashing with them. Set `theme.enable = false` for the
# untouched originals.
#
# (The single stylix wallpaper — `stylix.image` — is themed separately by
# _styling/wallpaper.nix, which uses gowall. That one drives colour *generation*;
# these are just pictures, so plain imagemagick is enough.)
#
# The directory is assembled with linkFarm rather than copied into $HOME, so the
# images stay in the store and cost nothing to "install". Drop your own files
# into `cosmos.desktops.wallpapers.directory` and they show up alongside these —
# the picker is pointed at that writable directory, with the defaults symlinked
# in on activation.
{...}: {
  den.aspects.home.wallpapers.homeManager = {
    config,
    lib,
    pkgs,
    ...
  }: let
    inherit (lib.options) mkOption mkEnableOption;
    inherit (lib.types) str path;

    cfg = config.cosmos.desktops.wallpapers;

    rev = "6bf4d733ebf2b484a37c17d742eb47e5139e6a14";
    fromWalls = name: hash:
      pkgs.fetchurl {
        inherit hash;
        url = "https://raw.githubusercontent.com/dharmx/walls/${rev}/digital/${name}";
      };

    sources = {
      "birds-in-the-sky.jpg" =
        fromWalls "a_group_of_birds_flying_in_the_sky.jpg"
        "sha256-v6KVInk5JJZPLkOAfC8yuDQtnZtT1DWQI7u6UfG59WY=";
      "road-orange-clouds.jpg" =
        fromWalls "a_car_on_a_road_with_orange_clouds_in_the_sky.jpg"
        "sha256-etcAxuS/sHme2jkiG/DAc4ZQxaiRBW02lWu0Z4i4SWo=";
      "road-purple-clouds.png" =
        fromWalls "a_car_on_a_road_with_purple_clouds_in_the_sky.png"
        "sha256-hO+qoDONQ7OCIfqSIqtuBANxHIDrggIp3UziYySXbfU=";
      "road-at-night.png" =
        fromWalls "a_car_driving_on_a_road_at_night.png"
        "sha256-Z82sql3x0W5+ppco2S0vRJC6tY+iTQuXGDyem5K0WGg=";
      "house-on-a-cliff.png" =
        fromWalls "a_cartoon_of_a_house_on_a_cliff.png"
        "sha256-W8A8io3hVRufXWko86BJC2bm+DliLT7l/3UKwFmMpQs=";
    };

    # A 16x1 swatch strip of the base16 palette — imagemagick's `-remap` takes
    # its target colours from an image, not a list.
    palette = let
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
    in
      pkgs.runCommand "base16-palette.png" {nativeBuildInputs = [pkgs.imagemagick];} ''
        magick ${lib.concatMapStringsSep " " (c: "'xc:${c}'") colors} +append png:$out
      '';

    # Dithering matters: a flat 16-colour remap posterises photographs into
    # banded blobs, Floyd–Steinberg keeps the gradients readable.
    themed =
      pkgs.runCommand "wallpapers-themed" {nativeBuildInputs = [pkgs.imagemagick];}
      ''
        mkdir -p $out
        ${lib.concatStringsSep "\n" (lib.mapAttrsToList (name: src: ''
            magick ${src} -dither FloydSteinberg -remap ${palette} "$out/${name}"
          '')
          sources)}
      '';

    plain = pkgs.linkFarm "wallpapers-plain" (
      lib.mapAttrsToList (name: path: {inherit name path;}) sources
    );
  in {
    options.cosmos.desktops.wallpapers = {
      directory = mkOption {
        type = str;
        default = "${config.home.homeDirectory}/Pictures/wallpapers";
        description = ''
          Directory the wallpaper picker browses. Seeded with the default
          backgrounds; your own images can be added freely.
        '';
      };

      theme.enable =
        mkEnableOption "recolouring the bundled backgrounds to the stylix palette"
        // {default = true;};

      defaultWallpaper = mkOption {
        type = str;
        default = "${cfg.directory}/birds-in-the-sky.jpg";
        description = ''
          Background used when the shell has no wallpaper picked yet. Must be a
          path inside `directory` so the picker shows it as selected.
        '';
      };

      defaults = mkOption {
        type = path;
        readOnly = true;
        default =
          if cfg.theme.enable
          then themed
          else plain;
        description = "Store directory holding the bundled default backgrounds.";
      };
    };

    config = {
      cosmos.system.impermanence.persist.directories = ["Pictures/wallpapers"];

      # Symlink the defaults into the (writable) picker directory. Existing
      # symlinks are re-pointed (the store path changes whenever the palette
      # does), dangling ones are pruned, and real files the user dropped in are
      # never touched.
      home.activation.defaultWallpapers = lib.hm.dag.entryAfter ["writeBoundary"] ''
        run mkdir -p ${lib.escapeShellArg cfg.directory}
        for _wp in ${lib.escapeShellArg cfg.directory}/*; do
          if [ -L "$_wp" ] && [ ! -e "$_wp" ]; then run rm -- "$_wp"; fi
        done
        for _wp in ${cfg.defaults}/*; do
          _dest=${lib.escapeShellArg cfg.directory}/"$(basename "$_wp")"
          if [ ! -e "$_dest" ] || [ -L "$_dest" ]; then
            run ln -sfn "$_wp" "$_dest"
          fi
        done
      '';
    };
  };
}
