# Deployment

The servers are deployed by hand from voyager with deploy-rs; pushing to `main` deploys nothing. A bare `deploy` covers the servers whose `deployByDefault` fact is true (endeavour, gaia); pioneer is deployed on its own, because copying a closure to its SD card takes far longer than everything else.

```bash
git pull                             # main is what the fleet should run
nix flake update && git commit -qm "chore(flake): update lock" flake.lock && deploy && git push
deploy .#pioneer                     # one host, from a clean tree; `deploy .` for every server
```

Commit before deploying: a host records the revision it was built from, and a dirty tree records `<parent>-dirty`, which never matches `main` and keeps `DeployBehind` firing until the next clean deploy.

- `deploy` is deploy-rs from the flake lock, not `nix run github:serokell/deploy-rs`: the nodes' `activate` is built from the same input, and a CLI of another version may not match it. It runs `nix flake check` first (its `deploy-activate` covers only the `deployByDefault` servers, so pioneer never slows a deploy down), builds every closure on voyager (offloaded to endeavour, see below), then activates the hosts one at a time. A host that does not confirm within the timeout rolls back, and so do the hosts that already succeeded in the same run.
- **Magic rollback rolls back on any failed activation.** A oneshot that fails during `switch-to-configuration` undoes the whole deploy: keep units that cannot succeed yet out of `multi-user.target` (see the comments in `services/netbird.nix` and `services/ntfy.nix`).
- The deploy goes over SSH to `deployAddress:2222` as root, with voyager's device key (or the YubiKey break-glass). gaia's address is `lvdar.nl`, not the mesh name, so a broken mesh or netbird-proxy can still be fixed from voyager. Nothing on the fleet pulls or holds a credential for another host.
- **Being behind is an alert, not a deploy.** Each server's node-exporter reports the revision it was built from (`nixos_configuration_info`) and its nixpkgs commit time; endeavour's `services.deploy-drift` reports the head of `main` from the knot's repository on disk (`nix_config_main_info`). Prometheus sends two fleet-wide alerts to ntfy, repeating every 12 h until resolved:
  - `DeployBehind`: a default-deployed server has run something other than `main` for an hour, either pushed but not deployed, or deployed from an unpushed or dirty tree. pioneer is left out: it trails `main` after every push.
  - `NixpkgsStale`: a server's nixpkgs is more than a week old, so it is time for the update line above. This one covers pioneer too, and is its reminder to run `deploy .#pioneer`.
- **The knot runs on endeavour** (knot2, `services.tangled`; a repo `did:plc:abcdef…` lives at `/tank/knot/repos/plc/ab/cdef…`) and is published through gaia. Deploys do not depend on it; pulls and pushes do. If pushes are refused, check the pusher's `org.tangled.key.sshKey` record on their PDS (knot2 caches keys for an hour).
- voyager switches itself with `nh os switch`; it is not a deploy-rs node.
- **The blog bypasses all of this**: `services.site` polls its own content repository and recompiles when it moves, so publishing a post is a push, not a deploy. Only the site's *code* arrives through the flake input.

## Remote builds

endeavour is voyager's nix remote builder (`services.remote-builder` on endeavour, `services.remote-builder.client` on voyager), and the fleet's only aarch64 emulator.

- **What is offloaded:** any build voyager's daemon schedules (`maxJobs = 8`, `speedFactor = 4`, so endeavour is preferred), and every `aarch64-linux` build, which only endeavour can run (binfmt QEMU). Outputs are copied back and voyager's attic watch-store pushes them.
- **Transport:** `ssh-ng://nix-ssh@<endeavour mesh IP>:2222`. The client authenticates with its own SSH host key (root-only, persisted, no extra secret); endeavour's host key is pinned by core.ssh. endeavour authorizes each client's key with `from="<client mesh IP>"` as defence in depth. The `nix-ssh` user is a trusted user there, so a client is root-equivalent on endeavour's daemon.
- **Who is a client:** any host including `.client`. It emits its `meshAddress` and `sshHostKey` facts on the `nix-builder-client` quirk, which endeavour collects; nothing names the client. Both facts must be set (asserted).
- **Off the mesh:** the connection times out after 5 s and x86_64 builds fall back to local; aarch64 builds fail.
- **pioneer**: `deploy .#pioneer` builds its aarch64 closure on endeavour and pushes it to the Pi. Its 16G card is tight; `nix-collect-garbage` there if a copy runs out of space.
- Checks on voyager: `cat /etc/nix/machines`, and `sudo nix store info --store 'ssh-ng://nix-ssh@<endeavour mesh IP>?ssh-key=/persist/etc/ssh/ssh_host_ed25519_key'` (the key must be named: it lives only in `/etc/nix/machines`, and without it root's ssh offers its own keys and is refused).
