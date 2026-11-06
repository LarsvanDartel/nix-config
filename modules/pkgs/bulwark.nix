# bulwark pinned ahead of nixpkgs — a version floor: Stalwart 1.0 needs
# Bulwark >= 1.18.0 (nixpkgs had 1.14.2). Inert, and warns, once nixpkgs
# reaches the pinned version (never a downgrade).
{...}: {
  nixpkgs.overlays = [
    (_final: prev: let
      version = "1.20.0";
    in {
      bulwark =
        if prev.lib.versionAtLeast prev.bulwark.version version
        then
          prev.lib.warn ''
            modules/pkgs/bulwark.nix: nixpkgs' bulwark is now ${prev.bulwark.version} (>= ${version}); delete the override.
          ''
          prev.bulwark
        else
          prev.bulwark.overrideAttrs (finalAttrs: old: {
            inherit version;

            src = old.src.override {
              tag = version;
              hash = "sha256-oNTAR2SOXbOuO2f53Tl3T+DdMrufJnuziB1AhjOdh0A=";
            };

            # overrideAttrs does not re-derive npmDeps from npmDepsHash.
            npmDeps = prev.fetchNpmDeps {
              inherit (finalAttrs) src;
              name = "bulwark-${version}-npm-deps";
              hash = "sha256-mcEfKiwb+zvic82Bnhgh1T9Yj0Ytam7VwtCR/ExMkFo=";
            };

            meta = old.meta // {changelog = "https://github.com/bulwarkmail/webmail/releases/tag/${version}";};
          });
    })
  ];
}
