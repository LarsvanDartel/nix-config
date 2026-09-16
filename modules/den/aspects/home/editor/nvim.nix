# home.nvim — the nixvim-based neovim. Implementation is ./_nvim (underscore
# = import-tree ignored); nixvim reaches it via the `inputs` home
# extraSpecialArg.
{...}: {
  flake-file.inputs.nixvim = {
    url = "github:nix-community/nixvim";
    inputs.nixpkgs.follows = "nixpkgs";
  };

  den.aspects.home.nvim.homeManager.imports = [
    ./_nvim
  ];
}
