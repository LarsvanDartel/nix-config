# home.krita — raster painting with the stylus.
{...}: {
  den.aspects.home.krita.homeManager = {pkgs, ...}: {
    home.packages = [pkgs.krita];
    cosmos.system.impermanence.persist = {
      directories = [".local/share/krita"];
      files = [".config/kritarc"];
    };
  };
}
