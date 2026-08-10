# services.arr.sonarr — TV.
{den, ...}: {
  den.aspects.services.arr.sonarr =
    (import ./_lib.nix).mkSimpleArr {
      name = "sonarr";
      defaultPort = 8989;
      libraryDir = "shows";
    }
    den.aspects.services.arr;
}
