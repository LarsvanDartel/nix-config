# home.comma — run a program from nixpkgs without installing it: `, cowsay hi`.
#
# nix-index-database ships the prebuilt index (a local one is a ~20 min build
# that stales with every lock move); its zsh integration also replaces
# "command not found" with the packages that would provide it — NixOS's own
# programs.command-not-found stays off so nothing fights over
# command_not_found_handler.
#
# Not in roles.home-base: ~100 MiB of index would land on pioneer's 89%-full
# 16 GB SD card (which has no interactive user anyway); included per host —
# roles.desktop-home on voyager, provides.to-users on endeavour and gaia.
# Store path per host, not shared over the mesh: the index is mmap-read on
# every lookup, and gaia's `,` must still answer with the mesh down.
{...}: {
  flake-file.inputs.nix-index-database = {
    url = "github:nix-community/nix-index-database";
    inputs.nixpkgs.follows = "nixpkgs";
  };

  den.aspects.home.comma.homeManager = {inputs, ...}: {
    imports = [inputs.nix-index-database.homeModules.nix-index];

    # Pulls in comma-with-db: comma wrapped to read the prebuilt index.
    programs.nix-index-database.comma.enable = true;

    # Both default true via the module's shared.nix, stated because they are
    # the point: the index is what resolves `,`, and symlinkToCacheHome puts
    # it where nix-index-aware tools look (~/.cache/nix-index/files).
    programs.nix-index = {
      enable = true;
      symlinkToCacheHome = true;
    };
  };
}
