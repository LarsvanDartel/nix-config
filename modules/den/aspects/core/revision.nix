# core.revision — stamps each built system with the commit it came from.
{inputs, ...}: {
  den.aspects.core.revision.nixos = {
    # Deliberate: every commit changes every host's toplevel. A -dirty suffix
    # means the host was built from a tree that cannot be reproduced.
    system.configurationRevision =
      inputs.self.rev
      or inputs.self.dirtyRev
      or "unknown";
  };
}
