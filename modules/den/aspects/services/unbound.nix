# services.unbound — recursive DNS + oisd blocklist. Owns the oisd inputs
# (referenced by hosts that build a blocklist, e.g. endeavour).
{...}: {
  flake-file.inputs = {
    oisd-big-unbound = {
      url = "https://big.oisd.nl/unbound";
      flake = false;
    };
    oisd-nsfw-unbound = {
      url = "https://nsfw.oisd.nl/unbound";
      flake = false;
    };
  };

  den.aspects.services.unbound.nixos = {
    config,
    lib,
    ...
  }: let
    inherit (lib.options) mkEnableOption mkOption;
    inherit (lib.modules) mkIf mkMerge;
    inherit (lib.types) port str nullOr;
    inherit (lib.lists) optional;

    cfg = config.cosmos.services.unbound;
    netbird = config.cosmos.services.netbird;
  in {
    options.cosmos.services.unbound = {
      port = mkOption {
        type = port;
        default = 53;
      };
      blocklist = mkOption {
        type = nullOr str;
        default = null;
      };
      mesh = {
        enable = mkEnableOption ''
          answering for NetBird peers, and resolving mesh names.

          Two halves of one job. The first opens access-control to the mesh
          range so peers may query at all — without it they are REFUSED,
          since the defaults below only admit loopback and RFC1918.

          The second is why this host could not resolve its own peers. The
          NetBird client wants to be the system resolver, but unbound holds
          :53 here, so it fell back to an ephemeral port and left unbound
          answering `*.lvdar.nl` from public DNS. A lookup of
          `gaia.nb.lvdar.nl` returned gaia's *public* address, so anything
          addressing a peer by name silently left the mesh — which is a trap
          well beyond DNS. Forwarding the mesh domain to the client's own
          resolver fixes it at the root
        '';

        range = mkOption {
          type = str;
          default = "100.64.0.0/10";
          description = "The CGNAT range NetBird assigns peer addresses from.";
        };

        resolver = mkOption {
          type = str;
          default = "127.0.0.1@15353";
          description = ''
            Where the local NetBird client answers mesh queries, in unbound's
            IP@port form. Must match cosmos.services.netbird.client
            .dnsResolverAddress — the agent picks an ephemeral port unless
            told otherwise, which is precisely what cannot be forwarded to.
          '';
        };
      };

      dns64 = {
        enable = mkEnableOption "dns64";
        prefix = mkOption {
          type = str;
          default = "64:ff9b::/96";
        };
      };
    };

    config = {
      cosmos.system.impermanence.persist.directories = with config.services.unbound; [
        {
          directory = stateDir;
          inherit user group;
          mode = "0750";
        }
      ];
      services.unbound = {
        enable = true;
        resolveLocalQueries = true;
        settings = mkMerge [
          {
            server = {
              interface = ["0.0.0.0" "::0"];
              tls-system-cert = "yes";
              port = cfg.port;
              access-control =
                [
                  "127.0.0.0/8 allow"
                  "::1 allow"
                  "192.168.0.0/16 allow"
                  "10.0.0.0/8 allow"
                  "172.16.0.0/12 allow"
                ]
                ++ optional cfg.mesh.enable "${cfg.mesh.range} allow";
              private-address = [
                "10.0.0.0/8"
                "172.16.0.0/12"
                "192.168.0.0/16"
                "169.254.0.0/16"
                "fd00::/8"
                "fe80::/10"
              ];
              include = optional (cfg.blocklist != null) cfg.blocklist;
              harden-glue = true;
              harden-dnssec-stripped = true;
              use-caps-for-id = false;
              prefetch = true;
              edns-buffer-size = 1232;
              hide-identity = "yes";
              hide-version = "yes";
            };
            remote-control.control-enable = true;
          }
          (mkIf cfg.mesh.enable {
            # The mesh domain is not in public DNS and is not DNSSEC-signed,
            # while its parent lvdar.nl is. Without domain-insecure the
            # validator rejects every forwarded answer as bogus and the whole
            # zone SERVFAILs — which looks exactly like the resolver being
            # down.
            server = {
              domain-insecure = netbird.dnsDomain;

              # Unbound refuses to send queries to loopback by default
              # (do-not-query-localhost defaults to yes), so the forward-zone
              # below is silently skipped and the whole mesh zone SERVFAILs
              # while the target answers perfectly when queried by hand. The
              # protection is against resolving via a local recursor by
              # accident; here loopback is exactly where the answer lives.
              do-not-query-localhost = "no";
            };

            forward-zone = [
              {
                name = "${netbird.dnsDomain}.";
                forward-addr = cfg.mesh.resolver;
                # No fallback to the public resolvers. They would answer with
                # the wildcard A record for lvdar.nl, which is the edge's
                # public address — the wrong answer, returned confidently,
                # which is worse than no answer.
                forward-first = "no";
              }
            ];
          })
          (mkIf cfg.dns64.enable {
            module-config = "dns64 validator iterator";
            dns64-prefix = cfg.dns64.prefix;
            server.do-nat64 = "yes";
          })
        ];
      };

      networking.firewall = {
        allowedUDPPorts = [cfg.port];
        allowedTCPPorts = [cfg.port];
      };
    };
  };
}
