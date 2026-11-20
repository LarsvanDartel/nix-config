# flake-parts — den framework wiring.
{inputs, ...}: {
  # den has no nixpkgs input, so there is nothing to `follows`.
  flake-file.inputs.den.url = "github:denful/den";

  imports = [inputs.den.flakeModule];
}
