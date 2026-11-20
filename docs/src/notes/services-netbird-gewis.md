# services.netbird-gewis

Source: `modules/den/aspects/services/netbird-gewis.nix`.

## Two agents on one host

The GEWIS client runs next to the fleet agent on `wt0`. NetBird hardcodes some host-wide state, and each environment variable on the GEWIS client moves one piece of it out of `wt0`'s way:

- **`NB_NFTABLES_TABLE`**: every agent deletes the `netbird` nftables table when it starts. Sharing the table, the two agents wipe each other's ACLs, and the fleet's ACL watchdog then restarts `wt0` into the conflict.
- **`NB_USE_LEGACY_ROUTING`**: every agent flushes routing table 7120 and its ip rules when it starts, which drops `wt0`'s routes (endeavour's LAN). Legacy routing puts the GEWIS routes in `main` instead, which `wt0`'s `lookup main suppress_prefixlength 0` rule reads first.
- **`NB_FWMARK_BASE`**: a separate fwmark range, so neither agent's mark matches act on the other's packets.

These variables were checked against NetBird 0.80.0. Re-check them after a NetBird upgrade that changes firewall or routing code.
