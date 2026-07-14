# nvim (nixvim). The implementation lives under ./_impl (import-tree ignores
# `_` paths), which keeps its own nested options/keymaps/languages/plugins
# structure. Language and plugin toggles (cosmos.cli.programs.nvim.languages.*)
# are set by whichever host imports this feature.
{...}: {
  flake-file.inputs.nixvim = {
    url = "github:nix-community/nixvim";
    inputs.nixpkgs.follows = "nixpkgs";
  };

  flake.modules.homeManager.common = ./_impl;
}
