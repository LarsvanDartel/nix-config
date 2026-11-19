# nginx pinned ahead of nixpkgs — a version floor: 1.30.7 fixes NGINX2Root
# (CVE-2026-123007, -123633, -123634, -121810, -113425). HTTP/2 can't be turned
# off instead: gaia's netbird.lvdar.nl carries management/signal gRPC. Inert,
# and warns, once nixpkgs reaches the pinned version (never a downgrade).
{...}: {
  nixpkgs.overlays = [
    (_final: prev: let
      version = "1.30.7";
    in {
      nginxStable =
        if prev.lib.versionAtLeast prev.nginxStable.version version
        then
          prev.lib.warn ''
            modules/pkgs/nginx.nix: nixpkgs' nginxStable is now ${prev.nginxStable.version} (>= ${version}); delete the override.
          ''
          prev.nginxStable
        else
          prev.nginxStable.overrideAttrs {
            inherit version;
            nginxVersion = version;
            src = prev.fetchurl {
              url = "https://nginx.org/download/nginx-${version}.tar.gz";
              hash = "sha256-JWW1yDcFDpWPcPsPc8SOK8pFQq00n9NW9G+wxyYQvG4=";
            };
          };
    })
  ];
}
