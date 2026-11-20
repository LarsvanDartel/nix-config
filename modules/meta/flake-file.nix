# flake-file — generates flake.nix from the modules' `flake-file.*` declarations; regenerate with `nix run .#write-flake`.
{inputs, ...}: {
  imports = [inputs.flake-file.flakeModules.default];

  flake-file = {
    description = "lvdar's NixOS config";

    outputs = "dendritic";

    inputs.flake-file.url = "github:denful/flake-file";
  };
}
