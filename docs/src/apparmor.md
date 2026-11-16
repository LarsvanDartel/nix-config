# AppArmor

`core.apparmor` (in `roles.default`, so every host) turns on AppArmor and loads [apparmor.d](https://github.com/roddhjav/apparmor.d) profiles plus a few hand-written ones. Every policy shares one mode, `cosmos.security.apparmor.state`. It is **`complain`** for now; switching to `enforce` is a single change, made after reviewing the logs.

## Pieces

- **`pkgs.apparmor-d`** (`modules/pkgs/apparmor-d.nix`): apparmor.d built with its `prebuild` tool for NixOS.
  - `@{bin}`/`@{sbin}`/`@{lib}` gain a `/{nix/store/*/,}` prefix, so profiles attach to `/nix/store/*/bin/<x>`.
  - A sed gives exec rules priorities. Without it, the store glob turns FHS "exact path beats glob" rules into `conflicting x modifiers` errors.
  - A second sed adds `attach_disconnected` to every profile header that lacks it (about a third of them; plain, without `attach_disconnected.path`, which upstream pairs with per-profile `@{att}` rules). Without it, a file or socket the process got from systemd (an activation socket, a path inside a sandboxed unit's mounts) fails with EACCES even in complain mode, and it isn't logged as `DENIED`. pcscd hung voyager's login this way: pam_u2f waited on it forever. smartd's start timed out on endeavour the same way.
  - nixpkgs' `roddhjav-apparmor-rules` is the raw, unbuilt source and is not loadable.
  - The rev is pinned. On a bump, `--replace-fail` fails loudly if upstream moved the `@{bin}`/`@{lib}` lines.
- **Coverage** (`cosmos.security.apparmor.coverage`):
  - `installed` (voyager, endeavour, gaia) loads `core/_apparmor/common.nix` plus the host's `hosts/_apparmor/<host>.nix`.
  - `daemons` (pioneer) loads only `core/_apparmor/daemons.nix`: running daemons and the privilege boundary. Parsing ~250 profiles is too slow on a Pi 3.
- **Hand-written profiles** for services apparmor.d doesn't cover. Each one sits next to its service:
  - `nginx` in `services/nginx.nix`;
  - `netbird-proxy` in `services/netbird.nix`;
  - `stalwart` in `services/stalwart.nix`;
  - `ntfy-sh` in `services/ntfy.nix`;
  - `agent-session` in `services/coding-agents.nix` (see [Networking & SSH](networking.md#coding-agents-on-endeavour)).

  These units run with `NoNewPrivileges`, so the profiles have no exec transitions: under NNP, a `Px` to another profile is refused.
- **Other policies:**
  - transmission keeps nixpkgs' own `bin.transmission-daemon` policy, but its mode follows `state`.
  - podman containers get podman's `containers-default`. It is always enforced, and podman applies it only because core puts `apparmor_parser` on each oci-container unit's `path`. podman generates the profile itself and includes `<tunables/global>` only if `/etc/apparmor.d/tunables/global` exists, so core forwards that file to apparmor-profiles' (apparmor.d ships only `tunables/*.d`). Without it, the profile fails to parse and every container fails to start.
  - docker (endeavour) stays unconfined: moby only looks for `/sbin/apparmor_parser`.

## Traps

- **Complain mode still enforces explicit `deny` rules.** The hand-written profiles' denies (secrets, `/persist`, other services' state) are live from day one. The NixOS drop-in `abstractions/base-strict.d/nixos` only widens access.
- **The LSM only loads after a reboot.** Enabling AppArmor puts `apparmor` into `lsm=`. Until the host reboots, `apparmor.service` is skipped (`ConditionSecurity=apparmor`).
- **Boot and switch cost.** nixpkgs' `apparmor.service` runs one `apparmor_parser` per policy, serially and without a cache, before `sysinit.target`; that added ~36 s to voyager's boot. Core replaces its `ExecStart`/`ExecReload` with `apparmor-load`, which loads every policy with one parallel (`-j auto`) call and uses the parser's cache in `/var/cache/apparmor/<key>` (persisted).
  - The parser won't cache a policy loaded with `--Complain`. So complain-state policies are expanded at build time (`apparmor_parser -p`, all includes inlined; includes can declare child profiles) and get `complain` written into every profile header, which is what `aa-complain` does. The loader then passes no mode flag. For all 831 loaded policies this compiled byte-identical to `--Complain` (2026-11-16). The build fails if a complain policy ends up without a complain header.
  - Enforce-state policies load as written, as nixpkgs did. The roughly 60 apparmor.d profiles that ship `flags=(complain)` stay in complain mode even when `state = "enforce"`.
  - `<key>` hashes the `/etc/apparmor.d` farm (policies and includes), the mode-rewritten policy copy, the parser config and the parser. Store mtimes never change, so the parser alone can't tell that a profile changed. Any change gets a new directory, and the old ones are deleted.
  - The parser keys a subdirectory on the running kernel's feature set and recompiles on its own after a kernel update.
  - A switch compiles into the new key, so the next boot only loads cached binaries.
  - Policy is not compiled at build time: the output depends on the running kernel's feature set. Binaries compiled against the declared `abi/5.0` differ from runtime ones (12 KB of 35 KB for pcscd on 6.18), and the kernel would accept them silently.
- **ssh reaches its child profiles by name.** NixOS has no `libexec/openssh/`, so `sshd-session`, `sshd-auth` and `sftp-server` attach through `px` rules in `local/sshd` and `local/sshd-session`, not by path.
- **Profiles core never loads:**
  - `systemd`, `systemd-user` and `sd*` are full-system policy.
  - `dbus-*` is pointless: dbus-broker is built without AppArmor.
  - `orca` collides with an unrelated binary.
  - `apparmor_parser` would confine the parser itself.
  - A set of desktop profiles still fails to compile on store paths.

  The list is `excluded` in `core/apparmor.nix`.

## Operating

- **Logs:** journald keeps the audit records; no auditd is needed. To list what complain mode would have blocked:

  ```bash
  journalctl -b --grep 'apparmor="ALLOWED"' | grep -o 'profile="[^"]*"' | sort | uniq -c | sort -rn
  ```

- **Status:** `sudo aa-status`, and `ps -eo label,comm` for per-process labels.
- **A profile breaks something:** look for `apparmor="DENIED"` lines naming it.
  - apparmor.d profile: add its name to `cosmos.security.apparmor.disabledProfiles` in the host's `nixos` body.
  - Hand-written profile: add the missing allow rule, or drop the `deny` line it hit.
- **New software:** profiles are matched by attachment path against what is installed or running. To regenerate the lists, follow the procedure in the header of `core/_apparmor/match.py` (it uses `collect.sh` per host).
- **Won't boot:** pick the previous generation in the boot menu. On GRUB/extlinux hosts, adding `apparmor=0` to the kernel cmdline also works.
