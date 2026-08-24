# Restoring a host

What to do when a machine is gone. Read the first section before you need it —
it is the part that cannot be fixed after the fact.

## The bootstrap problem, and the one thing you must keep offline

Every credential in this fleet is a sops secret, decrypted with an age key. There
are two age keys that can open endeavour's secrets:

| key | where it lives | decrypted by |
|---|---|---|
| `endeavour` host key | `/persist/etc/ssh/ssh_host_ed25519_key` | itself |
| `lvdar` user key | `~/.config/sops/age/keys.txt` on voyager — a **symlink to `/run/secrets/keys/age`** | voyager's host key |

`.sops.yaml` puts `&lvdar` on every creation rule, so the user key opens
everything. But it is itself a secret, so it only exists while voyager does. And
**voyager has no backup at all.**

That produces a loop. To restore endeavour you need its host key. The host key is
in the restic repository. Opening the repository needs `keys/stardust/password`
and `keys/stardust/ssh-key` — both sops secrets, i.e. both behind one of the two
keys above.

**So: the restic repository password and the storage-box SSH key must exist
somewhere outside the fleet — a password manager.** If both voyager and
endeavour are lost and those two values live only in sops, the backups cannot be
opened and nothing in this document works. Same for the PDS PLC rotation key,
which is not regenerable at all.

Check now, not later:

```bash
# these must be recoverable WITHOUT a working fleet host
#   - restic repository password   (keys/stardust/password)
#   - storage box SSH private key  (keys/stardust/ssh-key)
#   - PDS PLC rotation key         (keys/pds/…)
```

## Repositories

One Hetzner storage box, account `u649268`, one credential for both hosts:

- endeavour → `sftp:u649268@u649268.your-storagebox.de:/endeavour`
- gaia → `sftp:u649268@u649268.your-storagebox.de:/gaia`

The split is a convention, not a boundary — the same key reaches both, and there
is no append-only protection (port 23 is closed on the box), so a root compromise
can prune either. Treat the repository as recoverable-from, not tamper-proof.

## Restoring endeavour

Order matters. Steps 1 and 2 unlock everything else.

### 1. The host key first

```bash
export RESTIC_REPOSITORY='sftp:u649268@u649268.your-storagebox.de:/endeavour'
export RESTIC_PASSWORD_FILE=/path/to/password-from-your-password-manager
# restic reaches the box over sftp with the storage-box key:
export RESTIC_OPTIONS="sftp.command='ssh -p 22 -i /path/to/stardust-key -o BatchMode=yes u649268@u649268.your-storagebox.de -s sftp'"

restic snapshots
restic restore latest --target /mnt/restore --include /persist/etc
```

`/persist/etc` is ~20 KB and holds `ssh/ssh_host_ed25519_key` (the sops key),
`machine-id`, and `opencloud/opencloud.yaml`. Put the host key back at
`/persist/etc/ssh/` on the rebuilt machine before anything else — with it, the
machine can decrypt its own secrets and the rest is mechanical.

### 2. Unlock the pool

`keys/zfs/tank` is base64 in sops; `hosts/endeavour.nix` decodes it to
`/run/keys/zfs-tank.key` at boot. With the host key in place that happens on its
own. To do it by hand:

```bash
sops -d --extract '["keys"]["zfs"]["tank"]' hosts/endeavour/secrets.yaml \
  | base64 -d > /run/keys/zfs-tank.key
chmod 0400 /run/keys/zfs-tank.key
zpool import tank && zfs load-key -a
```

Recreate the pool from `hosts/_hw/endeavour/` (disko) if the disks are new. Note
the pool key is a *sops* secret: a pool created with a new key needs the secret
rerolled, not the other way round.

### 3. Everything else

```bash
restic restore latest --target /mnt/restore
```

Then place the rest: `/persist/var/lib/{kanidm,traccar,arr,grafana,pds,opencloud,
open-webui,nixos,radicale,suwayomi-server}`, `/persist/home`,
`/var/backup/postgresql`, and the `/tank/*` trees.

- **`/persist/var/lib/nixos`** is the uid/gid map. Restore it *before* starting
  services, or restored files get owners that no longer match.
- **Postgres** is a `pg_dumpall`, not a PGDATA copy — replay it:
  `psql -f /var/backup/postgresql/all.sql` (immich and others live in here).
- **NetBird is not backed up** on endeavour (`/persist/var/lib/netbird`).
  Re-enrol with a setup key from sops; the peer will get a new identity.
- Not backed up and not meant to be: jellyfin metadata, prometheus, loki, attic,
  spindle checkouts, ollama models, suwayomi downloads. All re-derive.

### 4. Verify before declaring success

```bash
systemctl status kanidm            # identity first — everything else logs in through it
zpool status tank
sudo -u postgres psql -l
curl -sI https://cloud.lvdar.nl    # end-to-end through gaia
```

## Restoring gaia

Simpler, and gaia's path list has always been restore-complete
(`/persist/etc` and `/persist/var/lib/nixos` were there from the start).

Same steps 1 and 3 with the `/gaia` repository. The order dependency that matters
here is different: **`/persist/var/lib/netbird-mgmt` is the mesh.** Losing
`store.db` means re-enrolling every peer on every device, including phones, and
re-issuing setup keys — while the mesh those devices use is down. Restore it
before anything else tries to reach the mesh.

`/persist/var/lib/acme` is restored too; without it a rebuild re-issues from
Let's Encrypt and can hit rate limits.

## The cold-start deadlock

If gaia comes up while endeavour is down, netbird-management cannot start: it
needs kanidm's discovery document, kanidm is on endeavour, and endeavour is only
reachable over the mesh that management brings up. `services/netbird.nix`
mitigates this with an nginx `proxy_cache` of the discovery document
(`inactive=365d`, `proxy_cache_use_stale`) at
`/var/cache/nginx/oidc-bootstrap` — which is **not** in gaia's backup paths and
is empty on a fresh machine.

This happened on 2026-08-12 and needed a reverse SSH tunnel and a hand-written
DNAT. If you are restoring both hosts, bring **endeavour's kanidm up first**, or
expect to do that again.

## Testing this

A backup that has never been restored is a belief. `restic.nix` runs
`--read-data-subset=5%` nightly, which proves the packs are readable, not that
the restore works.

Cheap test, no VM, run it periodically:

```bash
restic restore latest --target /tmp/restore-test \
  --include /persist/etc/ssh --include /persist/var/lib/nixos
test -s /tmp/restore-test/persist/etc/ssh/ssh_host_ed25519_key && echo "key present"
```

Then prove the key actually decrypts something — this is the step that validates
the whole chain, not just that files came back:

```bash
SOPS_AGE_KEY="$(ssh-to-age -private-key -i /tmp/restore-test/persist/etc/ssh/ssh_host_ed25519_key)" \
  sops -d --extract '["keys"]["zfs"]["tank"]' ~/nix-secrets/hosts/endeavour/secrets.yaml >/dev/null \
  && echo "chain intact"
rm -rf /tmp/restore-test
```
