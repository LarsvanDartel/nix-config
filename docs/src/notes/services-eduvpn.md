# services.eduvpn

Source: `modules/den/aspects/services/eduvpn.nix`.

## Mesh carve-out

eduvpn's ip rules (IPv4 priorities 2 and 3) beat NetBird's (105 and 110), and TU/e claims all of 100.64.0.0/10, so a connected eduvpn swallows the mesh even on the split profile. `eduvpn-mesh-priority` adds a priority-1 `lookup main` rule for each kernel route on the NetBird interface, one unit per NetBird client; the rules are inert while eduvpn is down. The prefixes are read off the interface, never hardcoded, so a pool change cannot silently break the mesh. The `fe80::/64` link-local route is skipped: it is not the mesh.

NetBird's own transport (fwmark `0x1bd00`) is deliberately *not* carved out. Under the full profile it falls through to eduvpn's table and runs nested in the campus tunnel; the split profile's peer only accepts TU/e prefixes, so there it keeps leaving via the uplink.

## Unit ordering

The unit is tied to the NetBird interface's device unit, not the agent's service: `netbird up` and `netbird down` toggle the interface inside a daemon that keeps running, so a service dependency would never fire. `multi-user.target` also wants it, so a `switch` with the mesh up starts it.

`DefaultDependencies=no` stops `multi-user.target` from ordering itself after this unit. Otherwise, with the mesh down, the device job sits out its 90 s timeout, and everything ordered after `multi-user.target` waits with it (power-profiles-daemon, and through its synchronous D-Bus activation the desktop shell). The defaults that still matter (`sysinit.target`, `basic.target`, `shutdown.target`) are restated explicitly.
