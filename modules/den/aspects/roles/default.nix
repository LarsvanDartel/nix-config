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
    core.revision
    # Failure *notifications* are in roles.server — see the note there.
    core.journald
    # Pull side only; serving stays on endeavour.
    services.attic.client
  ];
}
