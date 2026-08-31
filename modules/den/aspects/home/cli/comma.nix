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
# 100 MiB of database, which is why nothing here is in roles.home-base:
# home-base reaches every host through the user aspects, including pioneer,
# whose 16 GB SD card is 89% full and which has no interactive user to type `,`
# in the first place. So it is included one host at a time — roles.desktop-home
# for voyager, and provides.to-users on endeavour and gaia, which have the room
# and are exactly where you end up wanting a tool you did not install.
#
# Each host keeps its own copy of the store path rather than sharing one: the
# index is mmap-read on every lookup, so mounting it over the mesh would trade
# 100 MiB of disk for a network round trip on the one command whose whole point
# is being faster than looking the package up by hand — and it would leave gaia
# unable to answer `,` whenever endeavour or the mesh is down.
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
