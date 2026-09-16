# core.revision — stamp each built system with the commit it came from
# (`nixos-version --configuration-revision`; also the node-exporter label).
#
# Cost, deliberate: the toplevel derivation depends on the git revision, so
# every commit changes every host's toplevel even when nothing else did —
# cheap (the closure underneath is cached), but a no-op commit is no longer a
# no-op build and CI rebuilds the top level on every push. `dirtyRev` carries
# a -dirty suffix; seeing it on a host means the running system was built
# from a tree that does not exist in git and cannot be reproduced.
{inputs, ...}: {
  den.aspects.core.revision.nixos = {
    system.configurationRevision =
      inputs.self.rev
      or inputs.self.dirtyRev
      or "unknown";
  };
}
