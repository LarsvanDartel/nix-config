# services.arr.vpn — the network namespace the download clients are confined
# to, so that transmission and sabnzbd can only ever reach the internet through
# WireGuard. Owns the VPN-Confinement input, since nothing else uses it.
{
  den,
  inputs,
  ...
}: {
  flake-file.inputs.vpn-confinement.url = "github:Maroka-chan/VPN-Confinement";

  den.aspects.services.arr.vpn = {
    includes = [den.aspects.services.arr];
    nixos = {
      config,
      lib,
      pkgs,
      ...
    }: let
      inherit (lib.options) mkEnableOption mkOption;
      inherit (lib.modules) mkIf;
      inherit (lib.types) nullOr path listOf str port;
      inherit (lib.lists) optional;
      inherit (lib.meta) getExe;

      cfg = config.cosmos.services.arr.vpn;
    in {
      imports = [inputs.vpn-confinement.nixosModules.default];

      options.cosmos.services.arr.vpn = {
        name = mkOption {
          type = str;
          default = "wg";
        };
        configFile = mkOption {
          type = nullOr path;
          default = null;
        };
        postUp = mkOption {
          type = str;
          default = "";
        };
        accessibleFrom = mkOption {
          type = listOf str;
          default = [];
        };
        vpnTestService = {
          enable = mkEnableOption "the vpn test service";
          port = mkOption {
            type = nullOr port;
            default = null;
          };
        };
        openTcpPorts = mkOption {
          type = listOf port;
          default = [];
        };
        openUdpPorts = mkOption {
          type = listOf port;
          default = [];
        };
      };

      config = {
        assertions = [
          {
            assertion = cfg.configFile != null;
            message = "The arr.vpn feature requires cosmos.services.arr.vpn.configFile to be set.";
          }
        ];

        vpnNamespaces.${cfg.name} = {
          enable = true;
          openVPNPorts = optional (cfg.vpnTestService.port != null) {
            port = cfg.vpnTestService.port;
            protocol = "tcp";
          };
          # Every entry becomes a route inside the namespace, back out through
          # the bridge. Anything not listed is answered via the namespace's
          # default route — which is the tunnel — so the reply leaves through
          # the VPN and is never seen again.
          #
          # That is what made sabnzbd and transmission unreachable from the
          # mesh while working locally: their ports are DNAT'd into the
          # namespace in prerouting, so a request from gaia arrived fine and
          # the SYN/ACK went out of ProtonVPN. It presented as a plain timeout
          # with the packet absent from both hosts' filter chains, because
          # prerouting had already redirected it and the reply never came back.
          accessibleFrom =
            [
              "192.168.1.0/24"
              "192.168.0.0/24"
              "127.0.0.1"
              # NetBird's peer range, so the edge can reach these at all.
              "100.64.0.0/10"
            ]
            ++ cfg.accessibleFrom;
          wireguardConfigFile = cfg.configFile;
        };

        systemd.services.arr.postStart = cfg.postUp;

        # VPN-Confinement pings the WireGuard endpoint before configuring the
        # tunnel and gives up after five attempts, one second apart. That is
        # not enough at boot: network-online.target is reached when dhcpcd has
        # a lease, which is a while before the WAN actually carries traffic, so
        # arr-up ran into a dead network, failed, and took sabnzbd and
        # transmission — both BindsTo it — down with it until someone noticed.
        #
        # Type=oneshot forbids Restart=, so the unit cannot simply try again.
        # Waiting for the same precondition it does, with a budget measured in
        # minutes rather than seconds, means its own check then passes first
        # try. Parsing the endpoint out of the config here rather than pinging
        # something well-known keeps this honest: the thing waited for is
        # exactly the thing needed next.
        systemd.services.arr.serviceConfig.ExecStartPre = [
          (getExe (pkgs.writeShellApplication {
            name = "arr-wait-for-endpoint";
            runtimeInputs = with pkgs; [gnugrep gnused iputils];
            text = ''
              endpoint="$(grep -iE '^[[:space:]]*Endpoint[[:space:]]*=' ${cfg.configFile} \
                | head -n1 | sed -E 's/.*=[[:space:]]*//; s/[[:space:]]*$//')"
              # Strip the port; bracketed for IPv6, bare otherwise.
              host="$(sed -E 's/^\[(.*)\]:[0-9]+$/\1/; s/^([^]]*):[0-9]+$/\1/' <<<"$endpoint")"

              if [ -z "$host" ]; then
                echo "arr: no Endpoint in the wireguard config; leaving the wait to vpn-up" >&2
                exit 0
              fi

              echo -n "arr: waiting for wireguard endpoint '$host'"
              for _ in $(seq 1 120); do
                if ping -c 1 -W 1 "$host" >/dev/null 2>&1; then
                  echo " reachable"
                  exit 0
                fi
                echo -n .
                sleep 1
              done

              # Not fatal on its own: the network may be up while ICMP is
              # dropped, and vpn-up's own check is still to come. Failing here
              # would turn a slow boot into the very outage this prevents.
              echo
              echo "arr: endpoint '$host' still unreachable after 120s; continuing anyway" >&2
            '';
          }))
        ];

        systemd.services.vpn-test-service = mkIf cfg.vpnTestService.enable {
          enable = true;
          vpnConfinement = {
            enable = true;
            vpnNamespace = cfg.name;
          };
          script = let
            vpn-test = pkgs.writeShellApplication {
              name = "vpn-test";
              runtimeInputs = with pkgs; [util-linux unixtools.ping coreutils curl bash libressl netcat-gnu openresolv dig];
              text =
                ''
                  cd "$(mktemp -d)"
                  dig google.com
                  echo "/etc/resolv.conf contains:"
                  cat /etc/resolv.conf
                  echo "resolvconf output:"
                  resolvconf -l
                  echo ""
                  echo "Getting IP:"
                  curl -s ipinfo.io
                  echo -ne "DNS leak test:"
                  curl -s https://raw.githubusercontent.com/macvk/dnsleaktest/b03ab54d574adbe322ca48cbcb0523be720ad38d/dnsleaktest.sh -o dnsleaktest.sh
                  chmod +x dnsleaktest.sh
                  ./dnsleaktest.sh
                ''
                + (
                  if cfg.vpnTestService.port != null
                  then ''
                    echo "starting netcat on port ${toString cfg.vpnTestService.port}:"
                    nc -vnlp ${toString cfg.vpnTestService.port}
                  ''
                  else ""
                );
            };
          in "${vpn-test}/bin/vpn-test";
        };
      };
    };
  };
}
