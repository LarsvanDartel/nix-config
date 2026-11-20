# services.netbird

Source: `modules/den/aspects/services/netbird.nix`.

## Peer approval

The reconciler turns on `peer_approval_enabled` so that approving a person for a gated web page does not also let them into the mesh.

A person who logs in to a gated service gets a NetBird user record on their first token. `user_approval_required` holds that record blocked until an administrator approves it, and a blocked user cannot reach the service either, so approving them is the only way to let them use the page. Management refuses a new peer only while its user is pending, so an approved user can run `netbird up` and enrol a device. With peer approval off, that device is live at once and joins the `All` group.

With peer approval on, the new peer exists but stays pending, with no access, until it is approved separately. Keep it on even with `mesh.enforce`: it is the only thing between "may use a published page" and "is a peer".

## Mesh DNS scope

The `nix-resolver` nameserver group answers only for `dnsDomain` and the mesh-only names (unbound `localRecords`, fed by the `mesh-dns-record` quirk). It is not `primary`.

- **Not primary.** The fleet resolvers have mesh addresses only, peers connect by direct UDP on 51820, and no relay is deployed. On a network that blocks that UDP, such as a campus Wi-Fi, a primary group takes all name resolution on the machine down with the mesh. Scoped to the mesh domain, losing the mesh costs mesh names only. The trade-off is that roaming devices lose the fleet's ad-blocking resolver. Making the group primary again is safe only once a relay exists for the agent to fall back to.
- **Mesh-only names ride along.** Without them, peers resolve names like `idrac` through their uplink to the public `*.lvdar.nl` wildcard, which points at netbird-proxy. netbird-proxy has no such service and aborts the TLS handshake (`SSL_ERROR_INTERNAL_ERROR_ALERT`).
- **Addresses are looked up, not configured.** NetBird assigns a peer's address at enrolment, so a hardcoded address would leave the mesh pointing at nothing after a re-enrolment.
