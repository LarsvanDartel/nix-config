# services.idrac — reverse proxy publishing the BMC on the mesh.
{den, ...}: {
  # Never serve this from endeavour, the host the BMC exists to recover. Mesh-only,
  # no NetBird identity gate: kanidm runs on endeavour, down exactly when this is needed.
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
        cosmos.services.netbird.client.exposedPorts = [cfg.port];

        # A fresh TLS handshake to the BMC costs ~0.6s per request; the pool reuses connections.
        services.nginx.upstreams.idrac = {
          servers."${cfg.address}:443" = {};
          extraConfig = ''
            keepalive 16;
            keepalive_timeout 300s;
            keepalive_requests 1000;
          '';
        };

        # Keepalive needs `Connection:` empty, a websocket needs `upgrade`; the stock
        # $connection_upgrade map sends `close` on ordinary requests and defeats the pool.
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
            # Not proxyWebsockets: its map closes the upstream connection on every request.
            proxyWebsockets = false;
            extraConfig = ''
              # Accepted risk: the BMC's self-signed certificate names a service tag and
              # cannot be verified; the hop is one switch on the LAN.
              proxy_ssl_verify off;
              proxy_ssl_server_name on;

              # The firmware serves its UI only pre-gzipped, to clients accepting gzip;
              # recommendedProxySettings blanks Accept-Encoding, which 404s every page.
              proxy_set_header Accept-Encoding gzip;

              # The console and dashboard telemetry are websockets.
              proxy_http_version 1.1;
              proxy_set_header Upgrade $http_upgrade;
              proxy_set_header Connection $idrac_connection;

              # No `gunzip`: every browser accepts gzip, and it would make this Pi decompress everything.

              # Keep the original Host: the BMC builds redirects and CSRF checks from it,
              # and overriding it yields a comma-joined redirect that breaks login.

              # The BMC emits absolute URLs naming its LAN address; map them to this vhost.
              proxy_redirect https://${cfg.address}/ /;
              proxy_redirect http://${cfg.address}/ /;

              # The BMC's DH key is below modern OpenSSL's minimum ("dh key too small");
              # lowering the level on this LAN hop only is the sole way in.
              proxy_ssl_ciphers "DEFAULT:@SECLEVEL=0";
              proxy_ssl_protocols TLSv1 TLSv1.1 TLSv1.2;

              # The default 1m body limit 413s firmware and virtual-media uploads.
              client_max_body_size 2048m;

              # Firmware updates and console sessions outlast the default 60s read timeout.
              proxy_read_timeout 1800s;
              proxy_send_timeout 1800s;
            '';
          };
        };
      };
    };
  };
}
