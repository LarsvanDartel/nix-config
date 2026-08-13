# services.unbound — recursive DNS + oisd blocklist.
#
# The blocklists are **vendored** in ./_unbound rather than fetched as flake
# inputs, and that is a correctness fix, not tidying.
#
# They used to be `flake = false` inputs pointing at https://big.oisd.nl/unbound
# and its nsfw sibling. oisd regenerates those files continuously — the header
# of each snapshot carries a `# Version: YYYYMMDDHHMM` line — so the narHash in
# flake.lock describes a file that no longer exists at that URL within a day or
# so. Every machine here kept working anyway, because the fetched copy was
# already in its store and eval cache. The first environment with a genuinely
# cold store was CI, and it failed immediately:
#
#   error: mismatch in field 'narHash' of input
#          {"type":"file","url":"https://big.oisd.nl/unbound"}
#
# which means the same failure was waiting for any fresh machine, or for any
# rebuild after a garbage collection deep enough to drop those paths. A DNS
# blocklist is not something to discover you cannot rebuild during a recovery.
#
# The cost is 12 MB + 22 MB of sorted domains in git, ~4.8 MB compressed, and
# an explicit act to update — `nix run .#update-blocklists`. That is the right
# trade for the fleet's resolver: updates become a reviewable commit instead of
# a silent change in what the network can reach.
{...}: {
  den.aspects.services.unbound.nixos = {
    config,
    lib,
    pkgs,
    ...
  }: let
    inherit (lib.options) mkEnableOption mkOption;
    inherit (lib.modules) mkIf mkMerge;
    inherit (lib.types) port str nullOr bool;
    inherit (lib.lists) optional;
    inherit (lib.strings) splitString concatStringsSep;
    inherit (lib.lists) filter uniqueStrings;

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
        description = "Path to an unbound-format blocklist to include.";
      };

      # Lifted out of hosts/endeavour.nix so a second resolver can carry the
      # same list. A backup that answers but stops blocking ads is a confusing
      # failure mode — the whole point of a fallback is that you cannot tell
      # which one served you.
      oisd = {
        enable = mkEnableOption "the oisd blocklist";
        nsfw = mkOption {
          type = bool;
          default = false;
          description = "Also include the nsfw list on top of the big one.";
        };
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
      cosmos.services.unbound.blocklist = mkIf cfg.oisd.enable (
        let
          lines = str: filter (x: x != "") (splitString "\n" str);
          bigLines = lines (builtins.readFile ./_unbound/oisd-big.unbound);
          nsfwLines = lines (builtins.readFile ./_unbound/oisd-nsfw.unbound);
          merged =
            concatStringsSep "\n"
            (uniqueStrings bigLines ++ optional cfg.oisd.nsfw (concatStringsSep "\n" nsfwLines));
        in
          toString (pkgs.writeText "unbound-blocklist" merged)
      );

      # Ordering only, not a dependency: on a host where the agent had taken
      # :53 as the system resolver, it has to be moved aside before unbound can
      # bind. Without this the deploy fails with "address already in use" and
      # rolls back, which is unrecoverable without a manual restart — the new
      # config that moves the agent is the very thing being rolled back.
      systemd.services.unbound.after =
        optional cfg.mesh.enable
        "${config.services.netbird.clients.default.suffixedName}.service";

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
