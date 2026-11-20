# services.stalwart — Stalwart 1.x mail/CalDAV/CardDAV/JMAP server with kanidm logins and the JetEmail relay.
{den, ...}: let
  defaultDavPort = 8089;
  # A constant so mesh-dns-record stays static; inside *.lvdar.nl so the cert verifies.
  relayDomain = "mail-relay.lvdar.nl";
in {
  den.aspects.services.stalwart = {
    includes = [den.aspects.services.netbird.client];

    # Ungated: DAV clients carry their own credentials and can't follow a redirect, and Bulwark's
    # browser side calls JMAP here. Http.allowedEndpoints 404s all but /dav, /jmap and /.well-known.
    netbird-service = {host, ...}: {
      mail = {
        bearerAuth.enable = false;
        targets = [
          {
            peer = host.name;
            port = defaultDavPort;
          }
        ];
      };
    };

    mesh-dns-record = {host, ...}: {${relayDomain} = host.meshAddress;};

    # Every OAuth mail client (Thunderbird, Bulwark) must use this client: Stalwart accepts only
    # tokens whose `aud` is `stalwart` (acceptedAudiences below).
    kanidm-provision = {config, ...}: let
      cfg = config.cosmos.services.stalwart;
    in {
      groups.mail-users = {
        overwriteMembers = false;
        members = ["lvdar"];
      };
      oauth2.stalwart = {
        displayName = "Mail";
        public = true;
        # Thunderbird's loopback listener takes a random port.
        enableLocalhostRedirects = true;
        # Required by the module; no flow redirects here.
        originUrl = ["https://${cfg.hostname}/"];
        originLanding = "https://${cfg.hostname}";
        # preferred_username plus usernameDomain becomes the Stalwart account
        # `lvdar@lvdar.nl`, not the SPN `lvdar@auth.lvdar.nl`.
        preferShortUsername = true;
        scopeMaps.mail-users = ["openid" "profile" "email"];
      };
    };

    nixos = {
      config,
      lib,
      pkgs,
      modulesPath,
      ...
    }: let
      inherit (lib.options) mkOption;
      inherit (lib.types) port str listOf;

      cfg = config.cosmos.services.stalwart;
      cred = name: {
        "@type" = "File";
        filePath = "/run/credentials/stalwart.service/${name}";
      };
      when = cond: value: {
        "if" = cond;
        "then" = value;
      };
      # Expression variable `listener` is the NetworkListener `name`.
      meshRelay = "(listener == 'mesh-relay' || listener == 'mesh-relay-tls')";
      listener = name: protocol: bind: tls:
        {
          inherit name protocol;
          bind = [bind];
          useTls = true;
          implicitTls = false;
        }
        // tls;
      plain = {useTls = false;};
      implicit = {implicitTls = true;};
    in {
      # nixpkgs' module is 0.15-only; ./_stalwart is its 0.16+ rewrite from
      # nixpkgs PR #552103, vendored until it lands.
      disabledModules = lib.warnIf (builtins.pathExists (modulesPath + "/services/mail/stalwart/provision.nix")) ''
        modules/den/aspects/services/stalwart.nix: nixpkgs now ships services.stalwart.provision (PR #552103).
        Delete modules/den/aspects/services/_stalwart and this disabledModules/imports pair; port the changes listed in the vendored files' headers first.
      '' ["services/mail/stalwart.nix"];
      imports = [./_stalwart/default.nix ./_stalwart/provision.nix];

      options.cosmos.services.stalwart = {
        domain = mkOption {
          type = str;
          default = "lvdar.nl";
          description = "Mail domain; the catch-all covers all of it.";
        };

        hostname = mkOption {
          type = str;
          default = "mail.lvdar.nl";
          description = "Public name: MX target, IMAP/SMTP host, JMAP/DAV base URL and the published service.";
        };

        davPort = mkOption {
          type = port;
          default = defaultDavPort;
          description = "Mesh-only HTTP listener netbird-proxy targets for CalDAV/CardDAV/JMAP.";
        };

        adminPort = mkOption {
          type = port;
          default = 8088;
          description = ''
            Loopback-only management API: provisioning and stalwart-cli
            (`STALWART_URL=http://127.0.0.1:8088 STALWART_USER=admin`).
          '';
        };

        relayPort = mkOption {
          type = port;
          default = 2525;
          description = "Mesh-only unauthenticated relay listener.";
        };

        relayTlsPort = mkOption {
          type = port;
          default = 2465;
          description = ''
            The same relay with implicit TLS, served as ${relayDomain}. For
            clients that refuse plaintext SMTP (kanidm-mail-sender).
          '';
        };

        relayClients = mkOption {
          type = listOf str;
          default = [];
          description = "Mesh IPs allowed to relay through relayPort/relayTlsPort without auth.";
        };

        issuerUrl = mkOption {
          type = str;
          # The client is oauth2.stalwart above.
          default = "https://auth.lvdar.nl/oauth2/openid/stalwart";
          description = ''
            OIDC issuer that signs the access tokens Stalwart accepts. kanidm
            issues per client, so every OAuth mail client must use that one
            kanidm client.
          '';
        };
      };

      config = {
        sops.secrets = {
          "keys/stalwart/admin".restartUnits = ["stalwart.service"];
          "keys/jetemail/username".restartUnits = ["stalwart-provision.service"];
          "keys/jetemail/password".restartUnits = ["stalwart.service"];
        };

        # NoNewPrivileges unit: no exec transitions out of this profile.
        security.apparmor.policies.stalwart = {
          inherit (config.cosmos.security.apparmor) state;
          profile = ''
            abi <abi/5.0>,
            include <tunables/global>

            profile stalwart ${lib.getExe config.services.stalwart.package} flags=(attach_disconnected,mediate_deleted) {
              include <abstractions/base-strict>
              include <abstractions/nameservice>
              include <abstractions/ssl_certs>

              capability net_bind_service,

              network inet stream,
              network inet6 stream,
              network inet dgram,
              network inet6 dgram,
              network unix dgram,
              network unix stream,

              ${lib.getExe config.services.stalwart.package} mr,

              /var/lib/stalwart/ rw,
              /var/lib/stalwart/** rwkl,
              /var/cache/stalwart/ rw,
              /var/cache/stalwart/** rwkl,
              /run/credentials/stalwart.service/ r,
              /run/credentials/stalwart.service/{tls-cert,tls-key,jetemail-password} r,

              /run/systemd/notify w,
              /run/systemd/journal/socket w,

              @{PROC}/sys/vm/overcommit_memory r,
              @{sys}/kernel/mm/transparent_hugepage/** r,
              @{sys}/devices/system/cpu/{online,possible} r,
              @{sys}/fs/cgroup/** r,
              owner @{PROC}/@{pid}/{cgroup,mountinfo,stat,statm,status,limits} r,
              owner @{PROC}/@{pid}/task/ r,
              /tmp/ r,
              owner /tmp/** rwk,

              deny /run/credentials/stalwart.service/admin rwlkmx,
              deny /run/secrets{,.d}/** rwlkmx,
              deny /run/secrets-for-users{,.d}/** rwlkmx,
              deny /persist/** rwlkmx,

              include if exists <local/stalwart>
            }
          '';
        };

        services.stalwart = {
          enable = true;
          # `stalwart` is a warnAlias for 0.15, fatal under abort-on-warn.
          # stalwart_1 is pinned ahead of nixpkgs (pkgs/stalwart.nix).
          package = pkgs.stalwart_1;
          stateVersion = "26.11";
          url = "https://${cfg.hostname}";

          # STALWART_RECOVERY_ADMIN: a permanent admin in every mode, and the
          # login provisioning uses.
          admin = {
            enable = true;
            username = "admin";
          };

          # LoadCredential reads as root: no secret owners or acme group needed.
          credentials = {
            admin = config.sops.secrets."keys/stalwart/admin".path;
            jetemail-password = config.sops.secrets."keys/jetemail/password".path;
            tls-cert = "/var/lib/acme/lvdar.nl/fullchain.pem";
            tls-key = "/var/lib/acme/lvdar.nl/key.pem";
          };

          # Listener and role changes take effect only on the next stalwart restart.
          provision = {
            enable = true;
            urls = ["http://127.0.0.1:${toString cfg.adminPort}"];
            # MtaRoute.authUsername is a plain string, without a File variant.
            secretFiles.jetemail-username = config.sops.secrets."keys/jetemail/username".path;

            singletons = {
              SystemSettings = {
                defaultHostname = cfg.hostname;
                defaultDomainId = "#domain";
              };

              # Accounts appear on first OAuth login (inbound mail bounces until then). Password
              # logins accept only app passwords: kanidm holds no password Stalwart can check.
              Authentication = {
                directoryId = "#kanidm";
                # Must be set: empty default roles leave accounts unable to receive mail. Picked up on restart.
                defaultUserRoleIds = ["#role-user"];
                defaultGroupRoleIds = ["#role-group"];
                defaultAdminRoleIds = ["#role-admin"];
              };

              Http = {
                # Safe only because dav is reachable only from netbird-proxy, which replaces client-sent
                # forwarding headers, and admin only from loopback. Without it, auto-ban bans the proxy.
                clientIpSource = "xForwardedFor";
                forwardedHops = 1;
                # Bulwark (webmail.lvdar.nl) calls JMAP cross-origin with
                # bearer tokens; no ambient credentials ride along.
                usePermissiveCors = true;
                # Keeps the management API off the public name. Stalwart
                # exempts loopback peers, so check from a non-loopback address.
                allowedEndpoints = {
                  match = [(when "listener == 'admin' || contains(['dav', 'jmap', '.well-known'], split(path, '/')[1])" "200")];
                  "else" = "404";
                };
              };

              MtaStageAuth = {
                require = {
                  match = [
                    (when meshRelay "false")
                    (when "local_port != 25" "true")
                  ];
                  "else" = "false";
                };
                # Advertising AUTH on the relay makes Laravel's mailer attempt
                # it with its placeholder user@example.com credentials.
                saslMechanisms = {
                  match = [
                    (when meshRelay "false")
                    (when "local_port != 25 && is_tls" "[plain, login, oauthbearer, xoauth2]")
                  ];
                  "else" = "false";
                };
                # Only the owner (the catch-all target) may send as any address; other mail-users are
                # held to their own. `authenticated_as` is `<name>@<domain>`.
                mustMatchSender = {
                  match = [(when "authenticated_as == 'lvdar@${cfg.domain}'" "false")];
                  "else" = "true";
                };
              };

              MtaStageRcpt = {
                # Blocked addresses (docs/src/hosts.md#gaia) go non-local to fail with 550. Rewrite only those:
                # it replaces the envelope recipient, and the spam filter scores the rest FORGED_RECIPIENTS.
                rewrite = {
                  match = [(when "key_exists('blocked', rcpt)" "'blocked@blocked.invalid'")];
                  "else" = "false";
                };
                allowRelaying = {
                  match =
                    [(when "!is_empty(authenticated_as)" "true")]
                    ++ lib.optional (cfg.relayClients != []) (when "${meshRelay} && (${
                      lib.concatMapStringsSep " || " (ip: "remote_ip == '${ip}'") cfg.relayClients
                    })" "true");
                  "else" = "false";
                };
              };

              MtaStageData = {
                # The relay's clients are our own unsigned, unaligned services: filtered, their
                # notifications to the local mailbox land in Junk.
                enableSpamFilter = {
                  match = [(when meshRelay "false")];
                  "else" = "true";
                };
                # JetEmail signs via the jetemail._domainkey CNAME; Stalwart holds no keys.
                dkimSignDomain."else" = "false";
              };

              MtaOutboundStrategy.route = {
                match = [(when "is_local_domain(rcpt_domain)" "'local'")];
                "else" = "'jetemail'";
              };
            };

            objects = {
              # Tracers have no name, hence the match on the variant. reconcile drops file tracers:
              # ProtectSystem makes /var/log unwritable.
              Tracer = {
                reconcile = true;
                match = ["@type"];
                objects.journal = {
                  "@type" = "Journal";
                  enable = true;
                  level = "info";
                };
              };

              NetworkListener = {
                reconcile = true;
                match = ["name"];
                objects = {
                  smtp = listener "smtp" "smtp" "[::]:25" {};
                  submissions = listener "submissions" "smtp" "[::]:465" implicit;
                  imaps = listener "imaps" "imap" "[::]:993" implicit;
                  # Plaintext inside WireGuard. No STARTTLS: *.lvdar.nl doesn't
                  # cover gaia.nb.lvdar.nl, so clients would fail verification.
                  mesh-relay = listener "mesh-relay" "smtp" "[::]:${toString cfg.relayPort}" plain;
                  mesh-relay-tls = listener "mesh-relay-tls" "smtp" "[::]:${toString cfg.relayTlsPort}" implicit;
                  dav = listener "dav" "http" "[::]:${toString cfg.davPort}" plain;
                  admin = listener "admin" "http" "127.0.0.1:${toString cfg.adminPort}" plain;
                };
              };

              # The only certificate, so every TLS listener serves it. Read at
              # start; a renewal restarts stalwart (reloadServices below).
              Certificate = {
                reconcile = true;
                match = ["certificate"];
                objects.certificate = {
                  certificate = cred "tls-cert";
                  privateKey = cred "tls-key";
                };
              };

              Domain = {
                match = ["name"];
                objects.domain = {
                  name = cfg.domain;
                  # Unlike an MtaStageRcpt rewrite, the catch-all keeps the original recipient,
                  # so per-service aliases are not scored FORGED_RECIPIENTS.
                  catchAllAddress = "lars@${cfg.domain}";
                  certificateManagement."@type" = "Manual";
                  dkimManagement."@type" = "Manual";
                  dnsManagement."@type" = "Manual";
                };
              };

              # Every service gets its own alias (steam@) and its mail names the service in the subject,
              # so this +2.0 rule hits most legitimate mail. Upstream rule updates keep local scores.
              SpamTag = {
                match = ["tag"];
                objects.rcpt-local-in-subject = {
                  "@type" = "Score";
                  tag = "RCPT_LOCAL_IN_SUBJECT";
                  score = 0;
                };
              };

              # Built-in roles, matched only to reference them. Provisioning before Stalwart created them makes
              # empty roles where every login fails "Unauthorized access"; delete those and restart.
              Role = {
                match = ["description"];
                objects = {
                  role-user.description = "User";
                  role-group.description = "Group";
                  role-admin.description = "System Administrator";
                };
              };

              Directory = {
                match = ["description"];
                objects.kanidm = {
                  "@type" = "Oidc";
                  description = "kanidm";
                  issuerUrl = cfg.issuerUrl;
                  # Login name: kanidm's short username (preferShortUsername)
                  # plus the domain, so the account is `lvdar@lvdar.nl`.
                  claimUsername = "preferred_username";
                  usernameDomain = cfg.domain;
                  claimName = "name";
                  # kanidm's `aud` is the client id, not Stalwart's URL.
                  acceptedAudiences = ["stalwart"];
                  # kanidm grants only `openid profile email`; "interoperable" would block the x: methods,
                  # the only way to create app passwords.
                  unscopedTokens = "full";
                };
              };

              MtaRoute = {
                match = ["name"];
                objects.jetemail = {
                  "@type" = "Relay";
                  name = "jetemail";
                  host = "relay.jetsmtp.net";
                  port = 587;
                  protocol = "smtp";
                  implicitTls = false;
                  allowInvalidCerts = false;
                  authUsername = "@@jetemail-username@@";
                  authSecret = cred "jetemail-password";
                };
              };
            };
          };
        };

        # The cert itself comes from nginx's netbird vhosts; including
        # services.acme here would duplicate its extraDomainNames.
        systemd.services.stalwart = {
          wants = ["acme-lvdar.nl.service"];
          after = ["acme-lvdar.nl.service"];
          # Adds newer releases' permissions to the default role sets at each start; it never re-adds
          # a permission 1.0.0 already had and respects disabledPermissions.
          environment.STALWART_UPDATE_ROLE_PERMISSIONS = "true";
        };
        security.acme.certs."lvdar.nl".reloadServices = ["stalwart.service"];

        # The reload validates the OIDC directory against kanidm over the mesh, up ~1.5 min after boot:
        # retries ride that out, and RestartMode=direct keeps notify-failure to real outages.
        systemd.services.stalwart-provision = {
          startLimitBurst = 5;
          startLimitIntervalSec = 600;
          serviceConfig = {
            # Active after success, so a changed plan restarts it on switch.
            RemainAfterExit = true;
            # Its readiness probe loops forever on a wrong URL or a dead server.
            TimeoutStartSec = "5min";
            Restart = "on-failure";
            RestartMode = "direct";
            RestartSec = "30s";
          };
        };

        # Not the module's openFirewall: that would open dav/admin/relay globally.
        networking.firewall.allowedTCPPorts = [25 465 993];
        cosmos.services.netbird.client.exposedPorts = [cfg.davPort cfg.relayPort cfg.relayTlsPort];

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
