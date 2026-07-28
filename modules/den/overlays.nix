# flake.overlays.default — the local packages (modules/pkgs/*) as one overlay,
# composed at the FLAKE level from the flake-parts `nixpkgs.overlays` aggregator.
# den hosts consume it via `inputs.self.overlays.default` (in core.nixpkgs), which
# is a plain flake output computed independently of any host evaluation.
{
  lib,
  config,
  ...
}: {
  flake.overlays.default = lib.composeManyExtensions config.nixpkgs.overlays;
}
