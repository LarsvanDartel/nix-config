# services.unbound — recursive DNS + oisd blocklist.
#
# The blocklists are vendored in ./_unbound deliberately. As `flake = false`
# file inputs they broke: oisd regenerates the files continuously, so the
# locked narHash stops matching within a day and any cold store (CI, a fresh
# machine, a deep GC) fails eval. Vendoring makes updates a reviewable
# commit: `nix run .#update-blocklists`.
{...}: {
  den.aspects.services.unbound.nixos = {
    config,
    lib,
    pkgs,
    ...
  }: let
    inherit (lib.options) mkEnableOption mkOption;
    inherit (lib.modules) mkIf mkMerge;
    inherit (lib.types) port str nullOr bool listOf attrsOf;
    inherit (lib.lists) optional;
    inherit (lib.attrsets) genAttrs mapAttrsToList;
    inherit (lib.strings) splitString concatStringsSep;
    inherit (lib.lists) filter uniqueStrings;

    cfg = config.cosmos.services.unbound;
    netbird = config.cosmos.services.netbird;
  in {
    options.cosmos.services.unbound = {
      localRecords = mkOption {
        type = attrsOf str;
        default = {};
        example = {"printer.example.org" = "10.0.0.4";};
        description = ''
          Names this resolver answers itself, as name -> IPv4.

          For a name that must resolve differently here than in public DNS, or
          that must keep resolving when the host normally serving it is down.
          Set per host: the answers are deployment facts, not properties of a
          resolver.
        '';
      };

      port = mkOption {
        type = port;
        default = 53;
      };
      firewallInterfaces = mkOption {
        type = nullOr (listOf str);
        default = null;
        example = ["wt0"];
        description = ''
          Interfaces to open the DNS port on, or null to open it on all of them.

          null is the default because getting this wrong is expensive: this is a
          mesh resolver (see mesh.resolvers), so a host that stops answering :53
          takes name resolution with it, and comin cannot fetch a fix over a
          network it can no longer resolve.

          Worth setting on a host with a public interface. access-control
          already REFUSES anything outside loopback, RFC1918 and the mesh, so an
          unscoped port is not an open resolver — but on a public VPS it is
          still a listener the internet can reach, and scoping it to the mesh
          interface removes that surface.
        '';
      };
      blocklist = mkOption {
        type = nullOr str;
        default = null;
        description = "Path to an unbound-format blocklist to include.";
      };

      # Lifted out of hosts/endeavour.nix so a second resolver can carry the
      # same list. A backup that answers but stops blocking is a confusing
      # failure: the point of a fallback is that you cannot tell which one
      # served you.
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

      # Ordering only, not a dependency: where the agent had taken :53 as the
      # system resolver it must move aside before unbound can bind, else the
      # deploy fails "address already in use" and rolls back — unrecoverable,
      # because the config that moves the agent is what gets rolled back.
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
          (mkIf (cfg.localRecords != {}) {
            server = {
              # `static` per name, not `transparent`: transparent falls
              # through to the public answer, which here is the wildcard
              # pointing at the edge — the wrong address, returned
              # confidently. Same failure the mesh forward-zone below is
              # commented about.
              local-zone = mapAttrsToList (name: _: ''"${name}." static'') cfg.localRecords;
              local-data = mapAttrsToList (name: addr: ''"${name}. IN A ${addr}"'') cfg.localRecords;
            };
          })
          (mkIf cfg.mesh.enable {
            # The mesh domain is not in public DNS and not DNSSEC-signed
            # while its parent lvdar.nl is: without domain-insecure the
            # validator rejects every forwarded answer as bogus and the zone
            # SERVFAILs, which looks exactly like the resolver being down.
            server = {
              domain-insecure = netbird.dnsDomain;

              # Unbound refuses loopback targets by default
              # (do-not-query-localhost), so the forward-zone below would be
              # silently skipped and the mesh zone SERVFAILs while the target
              # answers fine by hand. The default guards against accidental
              # local recursors; here loopback is where the answer lives.
              do-not-query-localhost = "no";
            };

            forward-zone = [
              {
                name = "${netbird.dnsDomain}.";
                forward-addr = cfg.mesh.resolver;
                # No fallback to public resolvers: they would answer the
                # lvdar.nl wildcard (the edge's public address) — the wrong
                # answer, returned confidently, worse than none.
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

      # Global unless scoped, deliberately: this resolver serves the mesh and,
      # on endeavour, the home LAN, and a wrong interface list takes name
      # resolution down for everything depending on it — including comin,
      # which then cannot fetch the fix.
      networking.firewall = mkMerge [
        (mkIf (cfg.firewallInterfaces == null) {
          allowedUDPPorts = [cfg.port];
          allowedTCPPorts = [cfg.port];
        })
        (mkIf (cfg.firewallInterfaces != null) {
          interfaces = genAttrs cfg.firewallInterfaces (_: {
            allowedUDPPorts = [cfg.port];
            allowedTCPPorts = [cfg.port];
          });
        })
      ];
    };
  };
}
