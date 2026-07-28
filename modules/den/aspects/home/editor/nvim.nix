# home.nvim — the nixvim-based neovim. Reuses the existing implementation tree
# (modules/home/cli/programs/nvim/_impl, import-tree-ignored via the underscore).
# The nixvim input is declared by the legacy nvim module during migration.
{...}: {
  den.aspects.home.nvim.homeManager.imports = [
    ./_nvim
  ];
}
