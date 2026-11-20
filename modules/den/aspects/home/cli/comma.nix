# home.comma — run a nixpkgs program without installing it (`, cowsay hi`)
{
  den,
  lib,
  ...
}: {
  flake-file.inputs.nix-index-database = {
    url = "github:nix-community/nix-index-database";
    inputs.nixpkgs.follows = "nixpkgs";
  };

  # Not pioneer: no room for the ~100 MiB index on its SD card.
  # Fires once per user (den.schema.user.includes), so the include lands in that user's home.
  den.policies.comma = {host, ...}:
    lib.optional (host.name != "pioneer") (den.lib.policy.include den.aspects.home.comma);

  den.schema.user.includes = [den.policies.comma];

  den.aspects.home.comma.homeManager = {inputs, ...}: {
    imports = [inputs.nix-index-database.homeModules.nix-index];

    programs.nix-index-database.comma.enable = true;

    # Keep NixOS's programs.command-not-found off: it would also claim command_not_found_handler.
    programs.nix-index = {
      enable = true;
      symlinkToCacheHome = true;
    };
  };
}
