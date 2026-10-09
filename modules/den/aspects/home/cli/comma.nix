# home.comma — run a program from nixpkgs without installing it: `, cowsay hi`.
#
# NixOS's programs.command-not-found stays off so nothing fights over
# command_not_found_handler. Not in roles.home-base: ~100 MiB index would land
# on pioneer's nearly-full SD card.
{...}: {
  flake-file.inputs.nix-index-database = {
    url = "github:nix-community/nix-index-database";
    inputs.nixpkgs.follows = "nixpkgs";
  };

  den.aspects.home.comma.homeManager = {inputs, ...}: {
    imports = [inputs.nix-index-database.homeModules.nix-index];

    programs.nix-index-database.comma.enable = true;

    programs.nix-index = {
      enable = true;
      symlinkToCacheHome = true;
    };
  };
}
