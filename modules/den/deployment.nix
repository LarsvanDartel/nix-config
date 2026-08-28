# Facts about *this* deployment, applied to every host.
#
# Everything here is a value an aspect used to carry as an option default, which
# made the aspects unusable by anyone who is not this fleet and, worse, hid real
# configuration where nobody looks for it: a host file stopped describing what
# the host does, and the value could only be found by reading the module.
#
# Only values whose option exists on *every* host belong here — den applies this
# to all of them, so setting an option a host does not have is an eval error.
# Anything narrower goes in that host's own file.
{...}: {
  den.default.nixos = {
    # The binary cache. Fleet-wide because roles/default.nix gives every host
    # the pull side; the server itself is endeavour's, and says so there.
    cosmos.services.attic.client.serverUrl = "http://endeavour.nb.lvdar.nl:8090";
  };
}
