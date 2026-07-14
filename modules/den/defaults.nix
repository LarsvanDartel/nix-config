# den defaults: baseline batteries + HM-by-default. Validates that the `den`
# module arg and batteries are available from den.flakeModule.
{
  den,
  lib,
  ...
}: {
  # every user gets a home-manager environment unless overridden.
  den.schema.user.classes = lib.mkDefault ["homeManager"];

  # batteries + core aspects every host/user gets.
  den.default.includes = [
    den.batteries.define-user
    den.batteries.hostname
    den.batteries.primary-user
    den.aspects.core.nixpkgs
  ];
}
