# Hosts

|host|arch|role|
|---|---|---|
|`voyager`|x86_64|ThinkPad P1 gen3 laptop, nvidia, Hyprland + Zen browser. Compositor choice is a **boot-time** switch: the base config and a labelled `hyprland` specialisation are identical, and a `niri`/noctalia specialisation is a separate GRUB entry|
|`endeavour`|x86_64|the workhorse. jellyfin, immich, kanidm, traccar, opencloud/collabora, suwayomi + flaresolverr, ollama + librechat (chat.lvdar.nl, local models + OpenRouter) on a Tesla P100, tangled (knot + spindle), a PDS, minecraft (packwiz packs from the `modpacks` input, also served to players at packs.lvdar.nl), attic, `services.site` (lvdar.nl), DOMjudge (judge.lvdar.nl: podman containers with CHipCie practice contests; extra judge languages live in `services/domjudge/languages.nix`), the VPN-confined `*arr` stack, and the prometheus/grafana/loki/alloy monitoring. ZFS `tank` with sanoid/zed; restic offsite|
|`gaia`|x86_64|public VPS and the fleet's only ingress. Runs the self-hosted **NetBird control plane**, and `netbird-proxy` terminates TLS and forwards to endeavour over the mesh. Also crowdsec, ntfy, stalwart, unbound, the gatus status page, and the vhosts its own nginx serves directly (`localVhosts`). Pangolin used to be the ingress and is **decommissioned** — do not reintroduce it|
|`pioneer`|aarch64|Raspberry Pi 3; built on endeavour (binfmt) via voyager's remote builder, never on the Pi. Publishes endeavour's **iDRAC** (`services.idrac`) to the mesh — it shares nothing with endeavour but a switch, which is the whole point: out-of-band management proxied by the machine it exists to recover is not out-of-band|

Hardware comes from committed **nixos-facter** reports (`hosts/_facter/<host>.facter.json`) plus **disko** layouts in `hosts/_hw/<host>/`. voyager, endeavour and gaia use impermanence (pioneer does not).

## Host facts

Each host registers `den.hosts.<arch>.<host> = { users.<user> = {}; meshAddress; server; deployAddress; sshHostKey; }` in `modules/den/hosts/<host>.nix`; the facts are declared in `modules/den/schema.nix` and are plain data any module can read without evaluating that host.

|fact|meaning|
|---|---|
|`meshAddress`|NetBird mesh IPv4, assigned at enrolment; re-check after re-enrolling a peer|
|`server`|headless server: gets `roles.server`|
|`deployAddress`|what deploy-rs connects to (default `<host>.nb.lvdar.nl`; gaia uses `lvdar.nl`)|
|`sshHostKey`|the host's ed25519 SSH host public key (`ssh-ed25519 AAAA…`, no comment). Pinned in every host's `known_hosts` (core.ssh) and used by endeavour to authorize remote-build clients. Read it with `cut -d' ' -f1,2 /persist/etc/ssh/ssh_host_ed25519_key.pub` on the host (`/etc/ssh` on pioneer), or `ssh-keyscan -t ed25519 -p 2222 <host>.nb.lvdar.nl`. A reinstall with a fresh key updates this fact and `.sops.yaml` together|

## voyager

The laptop and the only workstation; switches locally with `nh os switch`.

## endeavour

The workhorse and the fleet's build machine: build-gate, flake-bump, and voyager's remote builder including aarch64 emulation ([Remote builds](deployment.md#remote-builds)). Hosts the knot that comin deploys every host from.

## gaia

The edge: NetBird control plane, `netbird-proxy`, `localVhosts`, oidc.idp.

## pioneer

Raspberry Pi 3 publishing endeavour's iDRAC. No comin: deployed with deploy-rs.
