# home.nvim — the nixvim-based neovim; implementation in ./_nvim.
{...}: {
  flake-file.inputs.nixvim = {
    url = "github:nix-community/nixvim";
    inputs.nixpkgs.follows = "nixpkgs";
  };

  den.aspects.home.nvim.homeManager.imports = [
    ./_nvim
  ];
}
