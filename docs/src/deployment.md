# Deployment

endeavour and gaia deploy themselves; pushing to `main` is *not* what deploys them:

```
push to main → knot (services.tangled on endeavour)
            → services.build-gate builds gaia+endeavour+voyager (pioneer excluded, aarch64)
            → green? fast-forward `deploy` branch
            → comin (endeavour + gaia) polls the knot over public HTTPS, self-deploys (~5 min)
```

- build-gate is the gate because comin has **no magic rollback**: nothing reaches the fleet until it has been built. `deploy` behind `main` means a build is failing — the gate doing its job, not a stuck deploy (`git log deploy..main`).
- comin pulls, so no credential anywhere grants root on the fleet. `testing` branch → `nixos-rebuild test` (activated, gone on reboot).
- **The knot runs on endeavour** (knot2, `services.tangled`; a repo `did:plc:abcdef…` lives at `/tank/knot/repos/plc/ab/cdef…`) and is published through gaia, so endeavour deploys itself from a remote it hosts. If the knot or gaia's proxy is down, nothing deploys anywhere — and a change that breaks either can cut off the path used to fix it. comin fetches through netbird-proxy like any visitor, and the proxy fails **closed** when crowdsec's LAPI is unreachable: on 2026-08-29 a crowdsec that lost a DNS race 403'd the whole published surface *and* comin for six hours. Check `curl -I` against a published service before blaming the knot. If pushes are refused, check the pusher's `org.tangled.key.sshKey` record on their PDS (knot2 caches keys for an hour).
- `services.flake-bump` (timer on endeavour) refreshes the lock and pushes to `main` when green — **always pull before pushing**.
- deploy-rs stays for manual/out-of-band deploys and hosts without comin (pioneer); voyager switches locally with `nh os switch`.
- **The blog bypasses all of this**: `services.site` polls its own content repository and recompiles when it moves, so publishing a post is a push, not a deploy. Only the site's *code* arrives through the flake input.

## Remote builds

endeavour is voyager's nix remote builder (`services.remote-builder` on endeavour, `services.remote-builder.client` on voyager), and the fleet's only aarch64 emulator.

- **What is offloaded:** any build voyager's daemon schedules (`maxJobs = 8`, `speedFactor = 4`, so endeavour is preferred), and every `aarch64-linux` build, which only endeavour can run (binfmt QEMU). Outputs are copied back and voyager's attic watch-store pushes them.
- **Transport:** `ssh-ng://nix-ssh@<endeavour mesh IP>:2222`. The client authenticates with its own SSH host key (root-only, persisted, no extra secret); endeavour's host key is pinned by core.ssh. endeavour authorizes each client's key with `from="<client mesh IP>"` as defence in depth. The `nix-ssh` user is a trusted user there, so a client is root-equivalent on endeavour's daemon.
- **Who is a client:** any host including `.client`. It emits its `meshAddress` and `sshHostKey` facts on the `nix-builder-client` quirk, which endeavour collects; nothing names the client. Both facts must be set (asserted).
- **Off the mesh:** the connection times out after 5 s and x86_64 builds fall back to local; aarch64 builds fail.
- **pioneer** is deployed from voyager: `nix run github:serokell/deploy-rs .#pioneer` builds its aarch64 closure on endeavour and pushes it to the Pi.
- Checks on voyager: `cat /etc/nix/machines`, `sudo nix store ping --store ssh-ng://nix-ssh@<endeavour mesh IP>`.
