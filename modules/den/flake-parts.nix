# den framework wiring. den is zero-dependency (no nixpkgs input to follow);
# its flakeModule produces nixosConfigurations from `den.hosts.*`.
{inputs, ...}: {
  flake-file.inputs.den.url = "github:denful/den";

  imports = [inputs.den.flakeModule];
}
