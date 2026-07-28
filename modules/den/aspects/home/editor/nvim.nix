# home.nvim — the nixvim-based neovim. Its implementation is the ./_nvim tree
# (import-tree-ignored via the underscore); nixvim reaches it via the `inputs`
# home extraSpecialArg.
{...}: {
  flake-file.inputs.nixvim = {
    url = "github:nix-community/nixvim";
    inputs.nixpkgs.follows = "nixpkgs";
  };

  den.aspects.home.nvim.homeManager.imports = [
    ./_nvim
  ];
}
