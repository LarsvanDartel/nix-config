# overlays — flake.overlays.default, the local packages composed from the nixpkgs.overlays aggregator.
{
  lib,
  config,
  ...
}: {
  flake.overlays.default = lib.composeManyExtensions config.nixpkgs.overlays;
}
