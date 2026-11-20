# roles.default — the baseline every host gets via den.schema.host.includes.
{den, ...}: {
  den.aspects.roles.default.includes = with den.aspects; [
    core.nix
    core.locale
    core.users-base
    core.impermanence-options
    core.ntfy-options
    core.networking
    core.sudo
    core.apparmor
    core.yubikey
    core.ssh
    core.sops
    core.revision
    # core.boot is opt-in per host and core.notify-failure is server-only (roles.server); keep both out of here.
    core.journald
    # Only where services.fwupd is on.
    core.firmware-updates
    services.attic.client
  ];
}
