# home.comma — run a program from nixpkgs without installing it: `, cowsay hi`.
#
# comma is useless without a nix-index database, and building one locally is a
# ~20 minute job over the whole channel that goes stale as soon as the lock
# moves. nix-index-database ships a prebuilt one, regenerated upstream, so the
# database arrives as a normal store path pinned by the lock like anything else.
#
# The module also turns on programs.nix-index, whose zsh integration replaces
# the "command not found" message with the packages that would provide it. That
# is the half worth having even when comma itself goes unused. NixOS's own
# programs.command-not-found is already off here, so nothing fights over
# command_not_found_handler.
#
# 101 MB of database, which is why this is in roles.desktop-home rather than
# roles.home-base: home-base reaches every host through the user aspects,
# including pioneer, whose 16 GB SD card is 89% full and which has no
# interactive user to type `,` in the first place.
{...}: {
  flake-file.inputs.nix-index-database = {
    url = "github:nix-community/nix-index-database";
    inputs.nixpkgs.follows = "nixpkgs";
  };

  den.aspects.home.comma.homeManager = {inputs, ...}: {
    imports = [inputs.nix-index-database.homeModules.nix-index];

    # Pulls in comma-with-db, a comma wrapped so it reads the prebuilt index
    # instead of expecting one in the cache.
    programs.nix-index-database.comma.enable = true;

    # Both default to true via the module's shared.nix, stated here because
    # they are the reason this aspect is worth including at all: the index is
    # what makes `,` resolve a name, and symlinkToCacheHome is what puts it
    # where a bare `nix-index`-aware tool looks (~/.cache/nix-index/files).
    programs.nix-index = {
      enable = true;
      symlinkToCacheHome = true;
    };
  };
}
