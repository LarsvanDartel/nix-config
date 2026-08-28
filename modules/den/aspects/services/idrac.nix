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
          default = 443;
          description = ''
            443, and it has to be. The BMC builds its own redirects from the
            Host header's *name* and assumes the standard port, so behind
            anything else it answers / with

              location: https://idrac.lvdar.nl/start.html

            and the browser lands on a port with nothing on it. This was 8443
            on the reasoning that the obvious port buys nothing for a
            mesh-only service; it buys working redirects and a URL with no
            port in it.
          '';
        };
      };

      config = {
        # Opened on the netbird interface alone. Nothing on the LAN side needs
        # this — a machine on the LAN can reach the BMC directly.
        cosmos.services.netbird.client.exposedPorts = [cfg.port];

        # Every request was paying a fresh TLS handshake to the BMC —
        # measured at 0.53-0.70s time-to-first-byte against 0.03s for the
        # client's own TLS to this host. The UI pulls about eighty files, so
        # that is most of a minute of pure handshaking. A keepalive pool makes
        # it once.
        services.nginx.upstreams.idrac = {
          servers."${cfg.address}:443" = {};
          extraConfig = ''
            keepalive 16;
            keepalive_timeout 300s;
            keepalive_requests 1000;
          '';
        };

        # Keepalive needs `Connection:` empty, while a websocket needs it set to
        # `upgrade`; nginx's stock $connection_upgrade map sends `close` for
        # ordinary requests, which defeats the pool. This keeps both working.
        services.nginx.appendHttpConfig = ''
          map $http_upgrade $idrac_connection {
            default upgrade;
            ""      "";
          }
        '';

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
            proxyPass = "https://idrac";
            # Not proxyWebsockets: it pins Connection to a map that closes the
            # upstream connection on every ordinary request. The equivalent
            # headers are set below, against a map that does not.
            proxyWebsockets = false;
            extraConfig = ''
              # The BMC's certificate is self-signed and names a service tag,
              # so there is nothing here that could verify. The hop is one
              # switch on the LAN, and the alternative is not a better
              # certificate but plaintext.
              proxy_ssl_verify off;
              proxy_ssl_server_name on;

              # The BMC negotiates a Diffie-Hellman key smaller than modern
              # OpenSSL will accept, and nginx refuses the handshake outright:
              #
              #   SSL_do_handshake() failed (SSL: error:0A00018A:
              #   SSL routines::dh key too small) while SSL handshaking to
              #   upstream
              #
              # curl on this host fails against it the same way, so it is the
              # firmware and not nginx. Dell will not be fixing an iDRAC of this
              # vintage, and the alternative to lowering the level is no access
              # to the BMC at all.
              #
              # Scoped to this proxy hop only — it does not touch the TLS this
              # server presents, which is the real wildcard and unaffected — and
              # that hop is one switch away on the LAN, to a device whose
              # certificate could never be verified anyway.
              # This firmware ships its web UI as pre-gzipped files only, and
              # serves them solely to a client that says it accepts gzip:
              #
              #   plain                  /start.html -> 404
              #   Accept-Encoding: gzip  /start.html -> 200
              #
              # NixOS's recommendedProxySettings sets `Accept-Encoding ""` so
              # that nginx can transform responses, which here meant the BMC
              # 404'd every page and the UI looked broken rather than
              # unreachable. `gunzip on` lets nginx decompress again for any
              # client that would not have asked for gzip itself.
              proxy_set_header Accept-Encoding gzip;

              # The console and the telemetry the dashboard polls are
              # websockets, so an upgrade still has to pass through.
              proxy_http_version 1.1;
              proxy_set_header Upgrade $http_upgrade;
              proxy_set_header Connection $idrac_connection;

              # gunzip is deliberately absent: it would have this Pi decompress
              # every response for the benefit of a client that did not ask for
              # gzip, and every browser does.

              # The original Host is forwarded unchanged, which matters: the
              # BMC builds its redirects and its CSRF checks from it. Overriding
              # it to the BMC's own address made it see two host values — the
              # override plus X-Forwarded-Host from the recommended settings —
              # and emit a redirect with both joined by a comma:
              #
              #   location: https://192.168.2.111, idrac.lvdar.nl/login.html
              #
              # which the browser cannot follow, so a successful login bounced
              # straight back to the login page.

              # The BMC also emits absolute URLs naming its own LAN address in
              # some responses; rewrite those back to this vhost so a client
              # that cannot route to the LAN still follows them.
              proxy_redirect https://${cfg.address}/ /;
              proxy_redirect http://${cfg.address}/ /;

              proxy_ssl_ciphers "DEFAULT:@SECLEVEL=0";
              proxy_ssl_protocols TLSv1 TLSv1.1 TLSv1.2;

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
