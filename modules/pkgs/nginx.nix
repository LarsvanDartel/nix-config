# nginx — pinned ahead of nixpkgs as a version floor for NGINX2Root (CVE-2026-123007 et al.); HTTP/2 must stay on for gaia's gRPC.
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
