# core.revision — stamp each built system with the commit it came from.
# Cost, deliberate: every commit changes every host's toplevel. A -dirty suffix
# on a host means it was built from a tree that cannot be reproduced.
{inputs, ...}: {
  den.aspects.core.revision.nixos = {
    system.configurationRevision =
      inputs.self.rev
      or inputs.self.dirtyRev
      or "unknown";
  };
}
