# flake-file: flake.nix is generated from `flake-file.*` declarations spread
# across the modules. Regenerate with `nix run .#write-flake`; the
# `check-flake-file` flake check enforces it stays in sync.
{inputs, ...}: {
  imports = [inputs.flake-file.flakeModules.default];

  flake-file = {
    description = "lvdar's NixOS config";

    # flake-parts + import-tree over ./modules.
    outputs = "dendritic";

    inputs.flake-file.url = "github:denful/flake-file";
  };
}
