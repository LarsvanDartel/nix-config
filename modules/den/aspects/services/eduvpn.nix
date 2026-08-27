# services.eduvpn — the eduVPN linux client, plus the two pieces of system
# configuration it needs to work here at all. Voyager-only: it is a client for
# TU/e's campus VPN, and no server has any use for it.
#
# The GUI drives NetworkManager directly — it writes a `eduVPN` WireGuard
# profile on every connect and deletes it on disconnect — so the user only
# needs the networkmanager group, which the primary-user battery already
# grants. Nothing here runs as a service. The persist dirs are `home.eduvpn`,
# mirroring how `home.steam` pairs with roles.gaming.
{den, ...}: {
  den.aspects.services.eduvpn = {
    # The mesh-priority rule below reads NetBird's client options, and there is
    # no sense in the coexistence fix without the thing it coexists with.
    includes = [den.aspects.services.netbird.client];

    nixos = {
      config,
      pkgs,
      utils,
      ...
    }: let
      netbird = config.services.netbird.clients.default;

      # Both halves of the eduvpn/netbird problem are routing-rule priority, so
      # they are worth stating together.
      #
      # eduvpn installs its rules at priorities 2 and 3 (v4), NetBird installs
      # its at 105 and 110. eduvpn therefore always wins, and its rule 3 —
      # `not from 0.0.0.0/0 fwmark <wg mark> table <eduvpn table>` — sends every
      # unmarked packet into eduvpn's table before NetBird's rules are ever
      # consulted.
      #
      # For the full-tunnel profile that table holds a default route, so it
      # swallows the mesh outright. For the *split* profile it swallows it too,
      # which is the surprising half: TU/e's split profile claims
      # 100.64.0.0/10 — the whole CGNAT range — and the NetBird mesh is a /16
      # inside it. Neither eduvpn nor NetBird is misbehaving; they were simply
      # both handed the same address space by their operators, and eduvpn holds
      # the lower priority.
      #
      # So carve the mesh back out ahead of eduvpn, at a priority eduvpn does
      # not use for v4 (it starts at 2). The rule is inert when eduvpn is down:
      # it sends mesh traffic to the main table, which is where it would have
      # gone anyway.
      #
      # The mesh's *transport* needs the same treatment for a different
      # reason. Under the full-tunnel profile eduvpn's table has a default
      # route, so NetBird's own encrypted packets — which carry NetBird's
      # fwmark, not eduvpn's — are diverted into it and the mesh runs nested
      # inside the campus tunnel. That works, since eduvpn's 1392 MTU has room
      # for NetBird's 1280 plus overhead, but it is slower for no benefit and
      # it fails outright if campus ever blocks outbound UDP to the relays.
      # Send anything already marked as NetBird transport straight to main.
      #
      # Nothing here is written down as a literal. NetBird's pool is allocated
      # by the management server on gaia and its fwmark is the agent's own
      # constant, so both are read back off the interface — a hardcode would be
      # a value only this file believes, and would break the mesh silently
      # rather than loudly if either ever changed.
      # `netbird up`/`down` create and destroy this, which is the signal the
      # unit below actually wants.
      deviceUnit = "sys-subsystem-net-devices-${utils.escapeSystemdPath netbird.interface}.device";

      meshPriority = pkgs.writeShellApplication {
        name = "eduvpn-mesh-priority";
        runtimeInputs = with pkgs; [iproute2 gawk wireguard-tools];
        text = ''
          iface=${netbird.interface}
          state=/run/eduvpn-mesh-priority.rules

          # One "family selector value" per line; every one of them ends up as
          # `ip <family> rule add priority 1 <selector> <value> lookup main`.
          # Keeping the selector split in two fields is what lets the apply
          # loop quote everything instead of relying on word splitting.
          wanted() {
            ip -4 -o route show dev "$iface" proto kernel 2>/dev/null |
              awk '{print "-4 to " $1}'
            # fe80::/64 is the link-local route every interface has; it is not
            # the mesh and must not be pulled out of eduvpn's table.
            ip -6 -o route show dev "$iface" proto kernel 2>/dev/null |
              awk '$1 != "fe80::/64" {print "-6 to " $1}'

            # `off` when the agent is running wireguard in userspace, where
            # there is no mark to match on. The prefix rules above still do
            # their half of the job, so that is a warning, not a failure.
            mark="$(wg show "$iface" fwmark 2>/dev/null || true)"
            if [ -n "$mark" ] && [ "$mark" != "off" ]; then
              echo "-4 fwmark $mark"
              echo "-6 fwmark $mark"
            else
              echo "no fwmark on $iface; mesh transport will nest inside a full tunnel" >&2
            fi
          }

          case "''${1-}" in
            start)
              # The agent brings the interface up before it has finished
              # registering, so the routes can lag the unit by a few seconds.
              rules=""
              for _ in $(seq 1 60); do
                rules="$(wanted)"
                [ -n "$rules" ] && break
                sleep 1
              done

              if [ -z "$rules" ]; then
                echo "no mesh prefix on $iface; leaving the rules alone" >&2
                exit 1
              fi

              printf '%s\n' "$rules" > "$state"
              printf '%s\n' "$rules" | while read -r fam sel val; do
                # Delete first: a `switch` re-runs this unit, and `ip rule add`
                # happily stacks duplicates.
                ip "$fam" rule del priority 1 "$sel" "$val" lookup main 2>/dev/null || true
                ip "$fam" rule add priority 1 "$sel" "$val" lookup main
              done
              ;;
            stop)
              # Replay what was actually added rather than deleting priority 1
              # blind — eduvpn uses v6 priority 1 for its own subnet, and the
              # interface may already be gone by the time we run.
              [ -r "$state" ] || exit 0
              while read -r fam sel val; do
                [ -n "$val" ] || continue
                ip "$fam" rule del priority 1 "$sel" "$val" lookup main 2>/dev/null || true
              done < "$state"
              rm -f "$state"
              ;;
          esac
        '';
      };
    in {
      environment.systemPackages = [pkgs.eduvpn-client];

      # Strict reverse-path filtering breaks any full-tunnel VPN that routes via
      # a policy rule, which here means eduvpn's non-split profile.
      #
      # The nixos rpfilter rule sits in mangle PREROUTING with `--validmark`, so
      # it repeats the route lookup using the packet's fwmark. A reply arriving
      # on the wireless interface has mark 0, and eduvpn's `not from 0.0.0.0/0
      # fwmark <wg mark>` rule therefore sends that lookup into eduvpn's own
      # table, whose default route points back down the tunnel. oif never
      # matches the interface the packet came in on, so the packet is dropped —
      # taking the WireGuard handshake response with it, and the proxyguard TCP
      # fallback after it. Only the split profile survived, because its table
      # holds prefixes rather than a default and the lookup falls through to
      # main.
      #
      # Loose only asks that a route to the source exist at all, which is the
      # right question on a machine with more than one routing table.
      networking.firewall.checkReversePath = "loose";

      systemd.services.eduvpn-mesh-priority = {
        description = "Keep the NetBird mesh reachable while eduvpn is connected";
        documentation = ["man:ip-rule(8)"];

        # Tied to the *interface*, not to the agent's unit. `netbird up` and
        # `netbird down` toggle the connection inside a daemon that keeps
        # running either way, so hanging this off netbird.service means it
        # never fires on the transitions that actually matter — and a `switch`
        # installs the unit without anything ever starting it, which is exactly
        # how this shipped dead the first time.
        #
        # wt0 appears and disappears with the connection, so binding to its
        # device unit gets both edges for free: the rules go in when there is a
        # mesh to protect and come out when there is not. multi-user.target is
        # listed as well so that a `switch` while the mesh is already up starts
        # it now rather than at the next toggle.
        #
        # BindsTo is a requirement, so `systemctl start` with the mesh down
        # does not fail — it queues, and sits there until wt0 exists. That
        # looks like a hang and is not one; there is simply nothing to do until
        # there is an interface. Bring netbird up and the queued job runs.
        after = [deviceUnit "${netbird.suffixedName}.service"];
        bindsTo = [deviceUnit];
        wantedBy = [deviceUnit "multi-user.target"];

        serviceConfig = {
          Type = "oneshot";
          RemainAfterExit = true;
          ExecStart = "${meshPriority}/bin/eduvpn-mesh-priority start";
          ExecStop = "${meshPriority}/bin/eduvpn-mesh-priority stop";
          # Booting offline, or before the agent has an address, is the normal
          # way to reach the timeout above. Retry rather than sit failed.
          Restart = "on-failure";
          RestartSec = 30;
        };
      };
    };
  };
}
