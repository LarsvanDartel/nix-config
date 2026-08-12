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
    # Every host should be able to say which commit it is running, including
    # pioneer — the one most likely to be quietly out of date.
    core.revision
    # A bounded journal is wanted on every host — a laptop has no more use for
    # four gigabytes of it than a Pi does. Failure *notifications* are not here
    # but in roles.server: see the note there.
    core.journald
    # Pull side of the binary cache only. Reading from a cache is universally
    # useful — voyager is the host that most wants it, since it builds
    # pioneer's aarch64 closure under emulation. Serving one is not, so
    # services.attic itself stays on endeavour.
    services.attic.client
  ];
}
