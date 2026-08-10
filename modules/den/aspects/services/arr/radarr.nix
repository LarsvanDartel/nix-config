# services.arr.radarr — movies.
{den, ...}: {
  den.aspects.services.arr.radarr =
    (import ./_lib.nix).mkSimpleArr {
      name = "radarr";
      defaultPort = 7878;
      libraryDir = "movies";
    }
    den.aspects.services.arr;
}
