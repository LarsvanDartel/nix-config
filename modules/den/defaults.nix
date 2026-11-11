# den defaults: baseline batteries + HM-by-default. Validates that the `den`
# module arg and batteries are available from den.flakeModule.
{
  den,
  lib,
  ...
}: {
  den.default.nixos.system.stateVersion = lib.mkDefault "25.11";
  den.default.homeManager.home.stateVersion = lib.mkDefault "25.11";

  den.schema.user.classes = lib.mkDefault ["homeManager"];

  # Users' provides.to-hosts (catt, kde-connect, taskwarrior) reach their hosts
  # only through this battery; den drops its transition default (#694).
  den.schema.host.includes = [den.aspects.roles.default den.batteries.mutual-provider];

  den.schema.user.includes = [
    (den.batteries.user-shell "zsh")
    den.aspects.roles.home-base
  ];

  den.default.includes = [
    den.batteries.define-user
    den.batteries.hostname
    den.batteries.primary-user
    den.aspects.core.nixpkgs
    den.aspects.core.home-manager
  ];
}
