# services.eduvpn — the eduVPN linux client, plus the two pieces of system
# configuration it needs to work here at all. Voyager-only: it is a client
# for TU/e's campus VPN, and no server has any use for it.
#
# The GUI drives NetworkManager directly and nothing runs as a service; the
# persist dirs are `home.eduvpn`, mirroring `home.steam`/roles.gaming.
{den, ...}: {
  den.aspects.services.eduvpn = {
    # The mesh-priority rule below reads NetBird's client options — the
    # coexistence fix is pointless without the thing it coexists with.
    includes = [den.aspects.services.netbird.client];

    nixos = {
      config,
      pkgs,
      utils,
      ...
    }: let
      netbird = config.services.netbird.clients.default;

      # eduvpn installs its rules at v4 priorities 2 and 3, NetBird at 105/110,
      # so eduvpn always wins: its rule 3 (`not from 0.0.0.0/0 fwmark <wg mark>
      # table <eduvpn table>`) sends every unmarked packet into eduvpn's table
      # before NetBird's rules are consulted. Even the *split* profile swallows
      # the mesh — TU/e claims 100.64.0.0/10, the whole CGNAT range the NetBird
      # mesh is a /16 inside. Neither side misbehaves; both were handed the same
      # address space, and eduvpn holds the lower priority.
      #
      # So carve the mesh back out at priority 1 (a v4 priority eduvpn does not
      # use). Inert when eduvpn is down: mesh traffic goes to main, where it
      # would have gone anyway. NetBird's own transport gets the same treatment
      # — under the full tunnel it would nest inside the campus tunnel (works
      # at 1392-vs-1280 MTU, but slower for nothing and dead if campus ever
      # blocks UDP to the relays).
      #
      # No literals: NetBird's pool and fwmark are read back off the interface
      # — a hardcode would be a value only this file believes and would break
      # the mesh silently if either changed.
      # `netbird up`/`down` create and destroy this — the signal the unit below wants.
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

      # Strict rp_filter breaks eduvpn's non-split profile: the nixos rpfilter
      # rule re-does the route lookup with the packet's fwmark, a reply on the
      # wireless interface has mark 0, eduvpn's rule sends that lookup into
      # eduvpn's table whose default route points back down the tunnel, oif
      # never matches the ingress interface, and the packet — WireGuard
      # handshake response included — is dropped. Loose only asks that a route
      # to the source exist, the right question with more than one routing table.
      networking.firewall.checkReversePath = "loose";

      systemd.services.eduvpn-mesh-priority = {
        description = "Keep the NetBird mesh reachable while eduvpn is connected";
        documentation = ["man:ip-rule(8)"];

        # Tied to the *interface*, not the agent's unit: `netbird up`/`down`
        # toggle the connection inside a daemon that keeps running either way,
        # so netbird.service never fires on the transitions that matter — and a
        # `switch` that installs the unit without starting it is exactly how
        # this shipped dead the first time. Binding to wt0's device unit gets
        # both edges for free; multi-user.target so a `switch` while the mesh
        # is already up starts it now. BindsTo queues rather than fails when
        # the mesh is down — not a hang; the queued job runs once wt0 exists.
        after = [deviceUnit "${netbird.suffixedName}.service"];
        bindsTo = [deviceUnit];
        wantedBy = [deviceUnit "multi-user.target"];

        serviceConfig = {
          Type = "oneshot";
          RemainAfterExit = true;
          ExecStart = "${meshPriority}/bin/eduvpn-mesh-priority start";
          ExecStop = "${meshPriority}/bin/eduvpn-mesh-priority stop";
          # Booting offline, or before the agent has an address, is the normal
          # way to reach the timeout; retry rather than sit failed.
          Restart = "on-failure";
          RestartSec = 30;
        };
      };
    };
  };
}
