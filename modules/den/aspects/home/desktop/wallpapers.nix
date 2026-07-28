# home.wallpapers — a small set of default backgrounds, linked into a directory
# the wallpaper picker (noctalia's WallpaperSelector / control centre) browses.
#
# The directory is assembled with linkFarm rather than copied into $HOME, so the
# images stay in the store and cost nothing to "install". Drop your own files
# into `cosmos.desktops.wallpapers.userDirectory` and they show up alongside
# these — the picker is pointed at that writable directory, with the defaults
# symlinked in on activation.
{...}: {
  den.aspects.home.wallpapers.homeManager = {
    config,
    lib,
    pkgs,
    ...
  }: let
    inherit (lib.options) mkOption;
    inherit (lib.types) str;

    cfg = config.cosmos.desktops.wallpapers;

    rev = "6bf4d733ebf2b484a37c17d742eb47e5139e6a14";
    fromWalls = name: hash:
      pkgs.fetchurl {
        inherit hash;
        url = "https://raw.githubusercontent.com/dharmx/walls/${rev}/digital/${name}";
      };

    defaults = {
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
      defaults = mkOption {
        readOnly = true;
        default = pkgs.linkFarm "wallpapers" (
          lib.mapAttrsToList (name: path: {inherit name path;}) defaults
        );
        description = "Store directory holding the bundled default backgrounds.";
      };
    };

    config = {
      cosmos.system.impermanence.persist.directories = ["Pictures/wallpapers"];

      # Symlink the defaults into the (writable) picker directory, leaving any
      # files the user put there untouched.
      home.activation.defaultWallpapers = lib.hm.dag.entryAfter ["writeBoundary"] ''
        run mkdir -p ${lib.escapeShellArg cfg.directory}
        for _wp in ${cfg.defaults}/*; do
          _dest=${lib.escapeShellArg cfg.directory}/"$(basename "$_wp")"
          [ -e "$_dest" ] || run ln -s "$_wp" "$_dest"
        done
      '';
    };
  };
}
