# den framework wiring. den is zero-dependency (no nixpkgs input to follow).
# Its flakeModule coexists with the existing flake-parts skeleton during the
# migration; it produces nixosConfigurations from `den.hosts.*` (none yet).
{inputs, ...}: {
  flake-file.inputs.den.url = "github:denful/den";

  imports = [inputs.den.flakeModule];
}
