# roles.default — the baseline every host gets (was the nixos `common`
# aggregate). Grown as the common baseline features are converted to aspects.
# Applied to every host via den.schema.host.includes (see defaults.nix).
{den, ...}: {
  den.aspects.roles.default.includes = with den.aspects; [
    core.nix
    core.locale
    core.users-base
  ];
}
