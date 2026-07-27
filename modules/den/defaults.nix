# den defaults: baseline batteries + HM-by-default. Validates that the `den`
# module arg and batteries are available from den.flakeModule.
{
  den,
  lib,
  ...
}: {
  # stateVersion defaults (hosts override per-host).
  den.default.nixos.system.stateVersion = lib.mkDefault "25.11";
  den.default.homeManager.home.stateVersion = lib.mkDefault "25.11";

  # every user gets a home-manager environment unless overridden.
  den.schema.user.classes = lib.mkDefault ["homeManager"];

  # every host gets the baseline role.
  den.schema.host.includes = [den.aspects.roles.default];

  # batteries + core aspects every host/user gets.
  den.default.includes = [
    den.batteries.define-user
    den.batteries.hostname
    den.batteries.primary-user
    den.aspects.core.nixpkgs
    den.aspects.core.home-manager
  ];
}
