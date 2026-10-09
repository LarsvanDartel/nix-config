# services.eduvpn — the eduVPN linux client (TU/e campus VPN), plus the two
# pieces of system configuration it needs to work here at all.
{den, ...}: {
  den.aspects.services.eduvpn = {
    includes = [den.aspects.services.netbird.client];

    nixos = {
      config,
      pkgs,
      utils,
      ...
    }: let
      netbird = config.services.netbird.clients.default;

      # eduvpn's ip rules (v4 priorities 2/3) beat NetBird's (105/110), and
      # TU/e claims all of 100.64.0.0/10, swallowing the mesh even on the split
      # profile. Carve the mesh and NetBird's own transport back out at
      # priority 1; inert when eduvpn is down. Pool and fwmark are read off the
      # interface, never hardcoded, so a change cannot silently break the mesh.
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

      # Strict rp_filter drops eduvpn's non-split replies (incl. the WireGuard
      # handshake): the fwmark-0 re-lookup lands in eduvpn's table and oif
      # never matches the ingress interface.
      networking.firewall.checkReversePath = "loose";

      systemd.services.eduvpn-mesh-priority = {
        description = "Keep the NetBird mesh reachable while eduvpn is connected";
        documentation = ["man:ip-rule(8)"];

        # Tied to wt0's device unit, not netbird.service: `netbird up`/`down`
        # toggle inside a daemon that keeps running, and this shipped dead the
        # first time. multi-user.target starts it on a `switch` with the mesh up.
        after = [deviceUnit "${netbird.suffixedName}.service"];
        bindsTo = [deviceUnit];
        wantedBy = [deviceUnit "multi-user.target"];

        serviceConfig = {
          Type = "oneshot";
          RemainAfterExit = true;
          ExecStart = "${meshPriority}/bin/eduvpn-mesh-priority start";
          ExecStop = "${meshPriority}/bin/eduvpn-mesh-priority stop";
          Restart = "on-failure";
          RestartSec = 30;
        };
      };
    };
  };
}
