# services.idrac — the BMC, reachable over the mesh.
#
# This exists because of a circular dependency that turned a 56-second watchdog
# reset into a seven-hour outage on 2026-08-28. iDRAC is on the home LAN and
# cannot join the mesh itself, so the only way to it was through a machine on
# that LAN — and the only always-on machine there is endeavour, the host the
# BMC exists to recover. Out-of-band management that runs through the in-band
# host is not out-of-band.
#
# So it is published from pioneer, which is on the same LAN and shares nothing
# else with endeavour. Two deliberate choices:
#
#   * Mesh only. Nothing is added to netbird.services on gaia and nothing is
#     reachable from the internet. A BMC grants power control, a console and a
#     foothold inside the LAN; Dell's firmware is not something to leave facing
#     the public, and it would have to be, because the usual NetBird identity
#     gate authenticates against kanidm — which runs on endeavour and is down
#     in the one scenario this is for. gaia.nix documents the same trap for
#     gatus.
#
#   * TLS terminates here. The BMC's own certificate is self-signed with
#     CN=idrac-<service-tag> and no subjectAltName at all, so it can never match
#     the name it is reached by; a browser warning on every visit trains exactly
#     the wrong reflex on the most sensitive endpoint in the house. nginx serves
#     the real wildcard instead and talks to the BMC over its own TLS with
#     verification off — that hop is a switch away on the LAN.
{den, ...}: {
  den.aspects.services.idrac = {
    includes = with den.aspects.services; [nginx netbird.client];

    nixos = {
      config,
      lib,
      ...
    }: let
      inherit (lib.options) mkOption;
      inherit (lib.types) port str;

      cfg = config.cosmos.services.idrac;
    in {
      options.cosmos.services.idrac = {
        address = mkOption {
          type = str;
          example = "192.168.2.111";
          description = ''
            The BMC on the LAN, as this host reaches it. No default: it is a
            fact about one network, and a wrong guess here proxies to whatever
            else answers on that address.
          '';
        };

        domain = mkOption {
          type = str;
          example = "idrac.example.org";
          description = ''
            The name this is served under. Must resolve to this host — see
            the resolver's localRecords — and must be covered by the
            certificate named below, since nothing here obtains one.
          '';
        };

        certificate = mkOption {
          type = str;
          example = "example.org";
          description = ''
            An `security.acme.certs` entry covering `domain`. Named rather than
            requested: the certificate this uses is a wildcard obtained for the
            whole deployment, not something this service should order.
          '';
        };

        port = mkOption {
          type = port;
          default = 8443;
          description = ''
            Not 443. This is a Pi that may later publish something else, and
            binding the obvious port for a service reachable only over the mesh
            buys nothing.
          '';
        };
      };

      config = {
        # Opened on the netbird interface alone. Nothing on the LAN side needs
        # this — a machine on the LAN can reach the BMC directly.
        cosmos.services.netbird.client.exposedPorts = [cfg.port];

        services.nginx.virtualHosts.${cfg.domain} = {
          onlySSL = true;
          useACMEHost = cfg.certificate;
          listen = [
            {
              addr = "0.0.0.0";
              inherit (cfg) port;
              ssl = true;
            }
          ];

          locations."/" = {
            proxyPass = "https://${cfg.address}";
            # The console and the telemetry the dashboard polls are websockets.
            proxyWebsockets = true;
            extraConfig = ''
              # The BMC's certificate is self-signed and names a service tag,
              # so there is nothing here that could verify. The hop is one
              # switch on the LAN, and the alternative is not a better
              # certificate but plaintext.
              proxy_ssl_verify off;
              proxy_ssl_server_name on;

              # Dell's web UI uploads firmware images and virtual media, and
              # the default 1m body limit truncates both with a 413 that the
              # interface reports as a generic failure.
              client_max_body_size 2048m;

              # A BMC is slow. The default 60s read timeout is enough to cut
              # off a firmware update or a console session mid-way.
              proxy_read_timeout 1800s;
              proxy_send_timeout 1800s;
            '';
          };
        };
      };
    };
  };
}
