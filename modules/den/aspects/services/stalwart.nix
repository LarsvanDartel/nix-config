# services.stalwart — Stalwart mail/CalDAV/CardDAV server; logins via kanidm
# OIDC, outbound via the JetEmail relay.
{den, ...}: {
  den.aspects.services.stalwart = {
    includes = [den.aspects.services.netbird.client];

    nixos = {
      config,
      lib,
      pkgs,
      ...
    }: let
      inherit (lib.options) mkOption;
      inherit (lib.types) port str listOf;

      cfg = config.cosmos.services.stalwart;
      # Stalwart expands these at start; the macro doesn't trim, so the
      # secret files must not end in a newline.
      cred = name: "%{file:/run/credentials/stalwart.service/${name}}%";
    in {
      options.cosmos.services.stalwart = {
        domain = mkOption {
          type = str;
          default = "lvdar.nl";
          description = "Mail domain; the catch-all covers all of it.";
        };

        hostname = mkOption {
          type = str;
          default = "mail.lvdar.nl";
          description = "Public name: MX target, IMAP/SMTP host, and the published DAV service.";
        };

        davPort = mkOption {
          type = port;
          default = 8089;
          description = "Mesh-only HTTP listener netbird-proxy targets for CalDAV/CardDAV.";
        };

        adminPort = mkOption {
          type = port;
          default = 8088;
          description = ''
            Loopback-only webadmin, reached over
            `ssh -p 2222 -L 8088:127.0.0.1:8088 gaia`.
          '';
        };

        relayPort = mkOption {
          type = port;
          default = 2525;
          description = "Mesh-only unauthenticated relay listener.";
        };

        relayClients = mkOption {
          type = listOf str;
          default = [];
          description = "Mesh IPs allowed to relay through relayPort without auth.";
        };

        userinfoUrl = mkOption {
          type = str;
          # Hand-synced with systems.oauth2.stalwart in services/kanidm.nix.
          default = "https://auth.lvdar.nl/oauth2/openid/stalwart/userinfo";
          description = ''
            Where bearer tokens are validated. kanidm signs access tokens per
            client and this endpoint is per client, so every OAuth mail client
            must use that one kanidm client.
          '';
        };
      };

      config = {
        sops.secrets = {
          "keys/stalwart/admin".restartUnits = ["stalwart.service"];
          "keys/jetemail/username".restartUnits = ["stalwart.service"];
          "keys/jetemail/password".restartUnits = ["stalwart.service"];
        };

        services.stalwart = {
          enable = true;
          # `stalwart` is a warnAlias (fatal under abort-on-warn). Module is
          # 0.15-only until nixpkgs ships its 0.16 module; that bump will need
          # a config rewrite.
          package = pkgs.stalwart_0_15;
          stateVersion = "26.11";

          # LoadCredential reads as root: no secret owners or acme group needed.
          credentials = {
            admin-password = config.sops.secrets."keys/stalwart/admin".path;
            jetemail-username = config.sops.secrets."keys/jetemail/username".path;
            jetemail-password = config.sops.secrets."keys/jetemail/password".path;
            tls-cert = "/var/lib/acme/lvdar.nl/fullchain.pem";
            tls-key = "/var/lib/acme/lvdar.nl/key.pem";
          };

          settings = {
            server.hostname = cfg.hostname;
            lookup.default = {
              inherit (cfg) hostname domain;
            };

            server.listener = {
              smtp = {
                bind = ["[::]:25"];
                protocol = "smtp";
              };
              submissions = {
                bind = ["[::]:465"];
                protocol = "smtp";
                tls.implicit = true;
              };
              imaps = {
                bind = ["[::]:993"];
                protocol = "imap";
                tls.implicit = true;
              };
              # Plaintext inside WireGuard. No STARTTLS: *.lvdar.nl doesn't
              # cover gaia.nb.lvdar.nl, so clients would fail verification.
              mesh-relay = {
                bind = ["[::]:${toString cfg.relayPort}"];
                protocol = "smtp";
                tls.enable = false;
              };
              dav = {
                bind = ["[::]:${toString cfg.davPort}"];
                protocol = "http";
                tls.enable = false;
              };
              admin = {
                bind = ["127.0.0.1:${toString cfg.adminPort}"];
                protocol = "http";
                tls.enable = false;
              };
            };

            certificate.default = {
              cert = cred "tls-cert";
              private-key = cred "tls-key";
              default = true;
            };

            authentication.fallback-admin = {
              user = "admin";
              secret = cred "admin-password";
            };

            # Accounts appear on first OAuth login, or earlier via the admin
            # API's /api/principal/deploy (inbound mail bounces until then).
            # Password logins accept only app passwords: kanidm holds no
            # password Stalwart can check.
            storage.directory = "kanidm";
            directory.kanidm = {
              type = "oidc";
              timeout = "15s";
              endpoint = {
                method = "userinfo";
                url = cfg.userinfoUrl;
              };
              fields = {
                # Also the IMAP/DAV login name; kanidm's short username
                # (preferShortUsername), so the account is `lvdar`.
                username = "preferred_username";
                email = "email";
                full-name = "name";
              };
            };

            # Only `rcpt` (the full address) is in scope here, not rcpt_domain.
            # The target is the account's kanidm mail address.
            session.rcpt.catch-all = [
              {
                "if" = "ends_with(rcpt, '@${cfg.domain}')";
                "then" = "'lars@${cfg.domain}'";
              }
              {"else" = false;}
            ];

            session.auth = {
              require = [
                {
                  "if" = "listener == 'mesh-relay'";
                  "then" = false;
                }
                {
                  "if" = "local_port != 25";
                  "then" = true;
                }
                {"else" = false;}
              ];
              # Advertising AUTH on the relay makes Laravel's mailer attempt
              # it with its placeholder user@example.com credentials.
              mechanisms = [
                {
                  "if" = "listener == 'mesh-relay'";
                  "then" = false;
                }
                {
                  "if" = "local_port != 25 && is_tls";
                  "then" = "[plain, login, oauthbearer, xoauth2]";
                }
                {"else" = false;}
              ];
              # Single-user server: lets the account send as catch-all addresses.
              # JetEmail still refuses non-lvdar.nl senders.
              must-match-sender = false;
            };

            # The relay's clients are our own services; unsigned and unaligned,
            # their notifications to the local mailbox otherwise land in Junk.
            session.data.spam-filter = [
              {
                "if" = "listener == 'mesh-relay'";
                "then" = false;
              }
              {"else" = true;}
            ];

            session.rcpt.relay =
              [
                {
                  "if" = "!is_empty(authenticated_as)";
                  "then" = true;
                }
              ]
              ++ lib.optional (cfg.relayClients != []) {
                "if" = "listener == 'mesh-relay' && (${
                  lib.concatMapStringsSep " || " (ip: "remote_ip == '${ip}'") cfg.relayClients
                })";
                "then" = true;
              }
              ++ [{"else" = false;}];

            queue.strategy.route = [
              {
                "if" = "is_local_domain('', rcpt_domain)";
                "then" = "'local'";
              }
              {"else" = "'jetemail'";}
            ];
            queue.route.local.type = "local";
            queue.route.jetemail = {
              type = "relay";
              address = "relay.jetsmtp.net";
              port = 587;
              protocol = "smtp";
              tls = {
                implicit = false;
                allow-invalid-certs = false;
              };
              auth = {
                username = cred "jetemail-username";
                secret = cred "jetemail-password";
              };
            };

            # JetEmail signs via the jetemail._domainkey CNAME. Stalwart holds
            # no keys, and its defaults reference signatures that don't exist.
            auth.dkim.sign = false;
            auth.arc.seal = false;

            http = {
              url = [
                {
                  "if" = "listener == 'admin'";
                  "then" = "'http://127.0.0.1:${toString cfg.adminPort}'";
                }
                {"else" = "'https://${cfg.hostname}'";}
              ];
              # The dav port is reachable only from netbird-proxy (mesh
              # firewall), admin only from loopback. Without this, auto-ban
              # would ban the proxy. Stalwart trusts the *first* XFF entry;
              # safe only because netbird-proxy replaces client-sent forwarding
              # headers (NB_PROXY_TRUSTED_PROXIES is loopback only).
              use-x-forwarded = true;
              # Keeps webadmin/API off the public name. Stalwart exempts
              # loopback peers, so check from a non-loopback address.
              allowed-endpoint = [
                {
                  "if" = "listener == 'admin' || contains(['dav', '.well-known'], split(url_path, '/')[1])";
                  "then" = "200";
                }
                {"else" = "404";}
              ];
            };
          };
        };

        # Certs are read via file macros at start, so a renewal needs a
        # restart; try-reload-or-restart restarts (no ExecReload). The cert
        # itself comes from nginx's netbird vhosts; including services.acme
        # here would duplicate its extraDomainNames.
        systemd.services.stalwart = {
          wants = ["acme-lvdar.nl.service"];
          after = ["acme-lvdar.nl.service"];
        };
        security.acme.certs."lvdar.nl".reloadServices = ["stalwart.service"];

        # Not the module's openFirewall: that would open dav/admin/relay globally.
        networking.firewall.allowedTCPPorts = [25 465 993];
        cosmos.services.netbird.client.exposedPorts = [cfg.davPort cfg.relayPort];

        cosmos.system.impermanence.persist.directories = [
          {
            directory = "/var/lib/stalwart";
            user = "stalwart";
            group = "stalwart";
            mode = "0700";
          }
        ];
      };
    };
  };
}
