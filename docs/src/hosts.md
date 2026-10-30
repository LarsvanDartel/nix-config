# Hosts

|host|arch|role|
|---|---|---|
|`voyager`|x86_64|ThinkPad P1 gen3 (moving to Framework Laptop 12, profile prepared), niri + noctalia (Umbriel specialisation), remote-builds on endeavour|
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

The laptop and the only workstation; switches locally with `nh os switch`. Builds offload to endeavour ([Remote builds](deployment.md#remote-builds)), and its sshd is reachable over the mesh only.

### Hardware

`hardwareProfile` in `modules/den/hosts/voyager.nix` selects the machine voyager currently is. Each profile is a plain module in `hosts/_hw/voyager/` plus the hardware aspects it includes; facter (`_facter/voyager.facter.json`) and disko (`_hw/voyager/disko.nix` on `/dev/nvme0n1`, LUKS + btrfs, 16 GiB swapfile) are shared.

- **`thinkpad-p1`** (current): ThinkPad P1 gen3, Intel + nvidia (PRIME offload, open driver), `hardware.thinkpad` (fan control, noctalia fan widget) and `hardware.fingerprint`, CUDA OBS.
- **`framework-12`** (prepared): Framework Laptop 12 — Intel Core 3 304 (Wildcat Lake) with the Xe3 iGPU on `xe`, Intel BE213 Wi-Fi 7, 16 GB DDR5 in one slot (single channel), 256 GB 2230 NVMe, 1920×1200 touchscreen on a 360° hinge, Framework stylus (MPP 2.0), backlit keyboard, no fingerprint reader, Ethernet expansion card. The profile pins `linuxPackages_latest` (Wildcat Lake needs ≥ 7.1) and loads `pinctrl_intel_platform` before `soc_button_array` for the tablet-mode switch, both behind `lib.warnIf` guards.

Moving is a runbook: [Moving voyager to the Framework 12](install.md#moving-voyager-to-the-framework-12).

**Hibernation** resumes through systemd's `HibernateLocation` EFI variable; no profile hard-codes `resume=`/`resume_offset=` (see [Hibernation](install.md#hibernation) for the fallback).

### Desktop

- **niri + noctalia** is the base desktop, behind the noctalia greeter (niri preselected). A second GRUB entry, **"umbriel + noctalia"**, boots the Umbriel compositor with the same shell for experimenting (`specialisation.umbriel`, built from `desktop/_umbriel/system.nix` and `home/desktop/_umbriel/home.nix`). Umbriel's keybinds copy niri's by hand; validate edits with `umbriel config validate`.
- **Tablet mode** (`desktop.tablet`): folding the hinge makes the firmware disable keyboard and touchpad, and the tablet-mode switch shows the on-screen keyboard (wvkbd, kept running hidden) and the noctalia dock (launcher button, pinned and running apps). niri's `switch-events` do both; under Umbriel a root `tablet-mode-osk` unit watching libinput shows only the keyboard. iio-niri rotates the screen from the accelerometer (under Umbriel: `umbriel-autorotate`). Touch and stylus are mapped to `eDP-1` and follow rotation. All of it is inert on hardware without the sensor or switch.
- **Touch gestures** (niri only; niri has none of its own, upstream PR [#3771](https://github.com/niri-wm/niri/pull/3771) is a draft): lisgd reads `/dev/input/touchscreen` (a udev symlink, `uaccess` for the seat user) and runs niri actions. One-finger swipes count only from a screen edge: up from the bottom toggles the overview, in from the left/right edge focuses the column on that side, down from the top opens the control center. Two fingers up from the bottom toggles the keyboard. Three and four fingers copy niri's touchpad gestures, the content following the fingers: three vertical switch workspaces, three horizontal switch columns, four up/down open/close the overview. Three fingers down from the top edge close the window. Unlike on the touchpad these fire once when the fingers lift (one workspace or column per swipe, within 0.8 s), and the window under the fingers sees the touches too. The `lisgd-niri` wrapper restarts lisgd when the accelerometer turns the screen, since lisgd reads the orientation only at startup.
- **Without a keyboard**: unlock LUKS with a YubiKey touch (FIDO2) and log in at the greeter with a YubiKey (u2f, empty password).
- **Apps** for the stylus and media: Xournal++ (notes, PDF annotation), Rnote, Krita, and mpv with the touch-friendly uosc UI.

## endeavour

The workhorse and the fleet's build machine: build-gate, flake-bump, and voyager's remote builder including aarch64 emulation ([Remote builds](deployment.md#remote-builds)). Hosts the knot that comin deploys every host from.

## gaia

The edge: NetBird control plane, `netbird-proxy`, `localVhosts`, oidc.idp.

## pioneer

Raspberry Pi 3 publishing endeavour's iDRAC. No comin: deployed with deploy-rs.

The iDRAC (iDRAC8, firmware 2.21, no Redfish) is reached on the LAN at `192.168.2.111`, over the mesh at `https://idrac.lvdar.nl`, and by SSH as `ssh idrac` (a jump through pioneer with the RSA `id_idrac` key; see `hosts/voyager.nix`).

- **Set iDRAC passwords in-band, letters and digits only.** Passwords with special characters, and passwords set through the web UI, can pass IPMI yet fail the web login with `RAC0212` (2026-10-30, both accounts). From endeavour, which needs no old password: `nix run nixpkgs#ipmitool -- user set password <id> "$pw" 20`, then `user test <id> 20 "$pw"` (ids: `root` 2, `lvdar` 3; `ipmitool user list 1`).
- `ipmitool mc reset cold` on endeavour restarts only the BMC (clears login blocks and stale web sessions); restart `ipmi-fan-control` on endeavour afterwards, since it fails while the BMC is away.
