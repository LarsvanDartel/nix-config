# flake.overlays.default — local packages (modules/pkgs/*), composed from the
# flake-parts nixpkgs.overlays aggregator. den hosts consume it via
# inputs.self.overlays.default (core.nixpkgs) — a plain flake output computed
# independently of any host evaluation.
{
  lib,
  config,
  ...
}: {
  flake.overlays.default = lib.composeManyExtensions config.nixpkgs.overlays;
}
