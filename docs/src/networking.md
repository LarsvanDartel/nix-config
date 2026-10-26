# Networking & SSH

## The mesh and publishing

- Hosts meet on a **NetBird mesh** (`<host>.nb.lvdar.nl`); the control plane is self-hosted on gaia.
- An app aspect becomes public by emitting a `netbird-service = {host, ...}: { <name> = {...}; }` entry (same shape as `cosmos.services.netbird.services.<name>`). gaia's netbird server collects them (`pipe.collect`, x86_64 only) into `cosmos.services.netbird.services`; the producer also appends its port to `cosmos.services.netbird.client.exposedPorts`. Entries are gated behind a NetBird identity check unless `bearerAuth.enable = false` (open because the app runs its own login). Gated: `suwayomi`, `sabnzbd`, `prowlarr`, `radarr`, `sonarr`, `lidarr`, `bazarr`, `lingarr`, `minecraft-control`. The reasoning for each entry sits next to it in the app's aspect — read it before changing gating.
- `cosmos.services.netbird.localVhosts` (gaia) is the escape hatch for domains netbird-proxy *cannot* carry: management rejects any domain that is not a label beneath the proxy's `baseDomain`, so the apex `lvdar.nl` 422s and is served by gaia's own nginx over the mesh instead. Side effect when debugging: the apex keeps working when the proxy does not.
- `cosmos.networking.edgeTerminated`: endeavour = `true` (gaia terminates TLS and forwards to each app's own port, so apps must bind `0.0.0.0` and local nginx vhosts are dropped), gaia = `false` (it *is* the edge). A new service answering locally but not publicly is almost always a missing bind/`edgeTerminated` issue.
- Smoke check when debugging publishing/ingress: `curl -I` against the public name (probes DNS → edge TLS → netbird-proxy → app).
