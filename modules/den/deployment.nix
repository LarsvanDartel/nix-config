# Deployment-wide facts, applied to every host (moved out of aspect defaults,
# which hid fleet-specific values inside generic modules).
# Only options that exist on *every* host belong here — a host without the
# option is an eval error. Anything narrower goes in that host's own file.
{...}: {
  den.default.nixos = {
    # Fleet-wide: roles/default.nix gives every host the pull side; the server
    # itself is endeavour's.
    cosmos.services.attic.client.serverUrl = "http://endeavour.nb.lvdar.nl:8090";
  };
}
