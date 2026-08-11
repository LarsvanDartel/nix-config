# roles.default — the baseline every host gets (was the nixos `common`
# aggregate, minus boot which is opt-in). Applied to every den host via
# den.schema.host.includes (see defaults.nix).
{den, ...}: {
  den.aspects.roles.default.includes = with den.aspects; [
    core.nix
    core.locale
    core.users-base
    core.impermanence-options
    core.networking
    core.sudo
    core.yubikey
    core.ssh
    core.sops
    # A bounded journal is wanted on every host — a laptop has no more use for
    # four gigabytes of it than a Pi does. Failure *notifications* are not here
    # but in roles.server: see the note there.
    core.journald
  ];
}
