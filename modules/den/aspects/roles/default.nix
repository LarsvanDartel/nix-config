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
    # Observability floor. Both are cheap enough for the Pi and useful on a
    # laptop, so they sit here rather than in roles.server: a bounded journal
    # is wanted everywhere, and a unit failing unnoticed is bad everywhere.
    core.journald
    core.notify-failure
  ];
}
