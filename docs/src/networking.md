# Networking & SSH

## The mesh and publishing

- Hosts meet on a **NetBird mesh** (`<host>.nb.lvdar.nl`); the control plane is self-hosted on gaia.
- An app aspect becomes public by emitting a `netbird-service = {host, ...}: { <name> = {...}; }` entry (same shape as `cosmos.services.netbird.services.<name>`). gaia's netbird server collects them (`pipe.collect`, x86_64 only) into `cosmos.services.netbird.services`; the producer also appends its port to `cosmos.services.netbird.client.exposedPorts`. Entries are gated behind a NetBird identity check unless `bearerAuth.enable = false` (open because the app runs its own login). Gated: `suwayomi`, `sabnzbd`, `prowlarr`, `radarr`, `sonarr`, `lidarr`, `bazarr`, `lingarr`, `minecraft-control`. The reasoning for each entry sits next to it in the app's aspect — read it before changing gating.
- `cosmos.services.netbird.localVhosts` (gaia) is the escape hatch for domains netbird-proxy *cannot* carry: management rejects any domain that is not a label beneath the proxy's `baseDomain`, so the apex `lvdar.nl` 422s and is served by gaia's own nginx over the mesh instead. Side effect when debugging: the apex keeps working when the proxy does not.
- `cosmos.networking.edgeTerminated`: endeavour = `true` (gaia terminates TLS and forwards to each app's own port, so apps must bind `0.0.0.0` and local nginx vhosts are dropped), gaia = `false` (it *is* the edge). A new service answering locally but not publicly is almost always a missing bind/`edgeTerminated` issue.
- Smoke check when debugging publishing/ingress: `curl -I` against the public name (probes DNS → edge TLS → netbird-proxy → app).

## SSH

Set by `core.ssh` (`modules/den/aspects/core/ssh.nix`) on every host.

- **Port 2222 only.** NetBird's SSH server owns `<mesh-ip>:22` (it answers with a misleading "Permission denied (password)"), so OpenSSH listens on :2222 everywhere; `home.ssh` sets `Port 2222` for `*.nb.lvdar.nl` and the bare server names. Public :22 on gaia is not OpenSSH: it is a kernel DNAT to the knot on `endeavour:2222`.
- **voyager is mesh-only**: `openFirewall = false`, and :2222 is opened on the NetBird interface alone (`cosmos.services.netbird.client.exposedPorts`). A laptop joins foreign networks.
- **Authorized keys** for root and the primary user are exactly the files listed in `modules/den/aspects/core/_ssh-keys/authorized.nix`: `id_voyager` (the workstation's device key) and two YubiKey FIDO2 resident keys. The installer ISO authorizes the same list. `PermitRootLogin prohibit-password`, no passwords, no keyboard-interactive. Servers hold no user identities, and agent forwarding is off.
- **Break-glass** when voyager's key is lost or rotated wrong: on any machine with OpenSSH, plug in a YubiKey and recover its handle with `ssh-keygen -K` (writes `id_ed25519_sk_rk_lvdar`), then `ssh -o IdentitiesOnly=yes -i id_ed25519_sk_rk_lvdar -p 2222 root@<host>.nb.lvdar.nl`. gaia is also reachable on `lvdar.nl:2222` when the mesh is down.
- **Host keys are pinned**, not trusted on first use: `programs.ssh.knownHosts` is built from each host's `sshHostKey` fact ([Hosts](hosts.md#host-facts)) for its name, deploy address and mesh address (each also as `[…]:2222`), plus `knot.lvdar.nl` for endeavour. build-gate and flake-bump push to the knot with `StrictHostKeyChecking=yes`.
- **endeavour accepts only `git` through gaia's DNAT.** DNAT'd internet clients arrive as gaia's mesh IP, so a `Match Address <gaia mesh> User *,!git` block disables public-key auth for every other user from that address. Admin access to endeavour is over the mesh from a peer, never via `knot.lvdar.nl`.
