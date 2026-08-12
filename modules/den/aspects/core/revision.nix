# core.revision — stamp each built system with the commit it came from.
#
# Nothing in this fleet could answer "which commit is gaia actually running?"
# With four hosts deployed by hand with deploy-rs, and no auto-deploy, that is
# a question worth being able to answer without guessing from timestamps —
# `nixos-version --configuration-revision` on the host, or the
# `system.nixos.configurationRevision` label on its node-exporter metrics, now
# says so directly. It is also the prerequisite for any drift report: you
# cannot compare a host against HEAD without knowing what the host is.
#
# The cost, stated plainly because it is real: this makes the top-level
# derivation depend on the git revision, so *every* commit changes *every*
# host's toplevel even when nothing else did. That is a cheap rebuild — the
# closure underneath is untouched and fully cached — but it does mean a
# no-op commit is no longer a no-op build, and CI will rebuild the top level
# on every push. Worth it for knowing what is deployed.
#
# `dirtyRev` is what a working tree with uncommitted changes reports, and it
# carries a `-dirty` suffix. Seeing that on a host is a feature: it says the
# running system was built from something that does not exist in git and
# therefore cannot be reproduced.
{inputs, ...}: {
  den.aspects.core.revision.nixos = {
    system.configurationRevision =
      inputs.self.rev
      or inputs.self.dirtyRev
      or "unknown";
  };
}
