# roles.default — the baseline every host gets, applied via
# den.schema.host.includes (see defaults.nix). boot is opt-in, not here.
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
    # Every host should know which commit it is running — pioneer most of
    # all, as the one most likely to be quietly out of date.
    core.revision
    # A bounded journal is wanted on every host. Failure *notifications* are
    # in roles.server — see the note there.
    core.journald
    # Pull side of the binary cache only: reading is universally useful
    # (voyager most — it builds pioneer's aarch64 closure under emulation),
    # serving is not, so services.attic stays on endeavour.
    services.attic.client
  ];
}
