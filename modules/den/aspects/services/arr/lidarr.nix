# services.arr.lidarr — music.
{den, ...}: {
  den.aspects.services.arr.lidarr =
    (import ./_lib.nix).mkSimpleArr {
      name = "lidarr";
      defaultPort = 8686;
      libraryDir = "music";
    }
    den.aspects.services.arr;
}
