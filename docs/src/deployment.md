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
- **The knot runs on endeavour** and is published through gaia, so endeavour deploys itself from a remote it hosts. If the knot or gaia's proxy is down, nothing deploys anywhere — and a change that breaks either can cut off the path used to fix it. comin fetches through netbird-proxy like any visitor, and the proxy fails **closed** when crowdsec's LAPI is unreachable: on 2026-08-29 a crowdsec that lost a DNS race 403'd the whole published surface *and* comin for six hours. Check `curl -I` against a published service before blaming the knot.
- `services.flake-bump` (timer on endeavour) refreshes the lock and pushes to `main` when green — **always pull before pushing**.
- deploy-rs stays for manual/out-of-band deploys and hosts without comin (pioneer); voyager switches locally with `nh os switch`.
- **The blog bypasses all of this**: `services.site` polls its own content repository and recompiles when it moves, so publishing a post is a push, not a deploy. Only the site's *code* arrives through the flake input.
