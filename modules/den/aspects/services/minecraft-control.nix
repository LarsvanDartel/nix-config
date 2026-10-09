# services.minecraft.control — a web page for running the Minecraft servers,
#
# Only start/stop need root, via path units that never see input; everything
# else uses group `minecraft` (console FIFO, log). Keep it that way.
#
# Not cockpit (a root terminal with extra steps). The console lets anyone
# reaching this page `op`/`ban`/`stop` — the gating kanidm group is server
# administration by design.
#
# Not sudo: roles/server.nix sets execWheelOnly, so non-wheel users are
# refused at exec; polkit is disabled on headless hosts.
#
# Authentication lives in gaia's gated netbird-proxy + kanidm `gatedServices`.
{den, ...}: {
  den.aspects.services.minecraft.control = {
    includes = [den.aspects.services.minecraft den.aspects.services.nginx];

    nixos = {
      config,
      lib,
      pkgs,
      ...
    }: let
      inherit (lib.options) mkOption mkEnableOption;
      inherit (lib.types) attrsOf ints listOf port str;
      inherit (lib.modules) mkIf;

      cfg = config.cosmos.services.minecraft.control;

      user = "minecraft-control";
      systemctl = "/run/current-system/sw/bin/systemctl";

      minecraft = config.cosmos.services.minecraft;
      unit = server: "minecraft-server-${server}.service";

      # nix-minecraft's systemd-socket console (0660 minecraft:minecraft).
      fifo = server: "/run/minecraft/${server}.stdin";

      # Not the journal: reading it needs systemd-journal/adm, i.e. every log.
      logFile = server: "${minecraft.dataDir}/${server}/logs/latest.log";

      # tmpfs, so a pending flag never survives a reboot.
      flagDir = "/run/minecraft-control";
      flag = server: verb: "${flagDir}/${verb}-${server}";

      # Desired state, not on tmpfs: present = "meant to be down". Without it
      # switch-to-configuration restarted stopped servers on every deploy
      # (`systemctl disable` doesn't help; .wants are regenerated).
      stateDir = "/var/lib/minecraft-control";
      stopped = server: "${stateDir}/${server}.stopped";

      script = name: text: pkgs.writeShellApplication {inherit name text;};

      # Status ping only. Not `mcstatus <addr> json`: it also runs a query,
      # which is disabled, so every call waited out a UDP timeout (3.24s).
      players =
        pkgs.writers.writePython3Bin "mc-players" {
          libraries = [pkgs.python3Packages.mcstatus];
        } ''
          import json
          import sys

          from mcstatus import JavaServer

          try:
              server = JavaServer("127.0.0.1", int(sys.argv[1]), timeout=3)
              status = server.status()
              print(json.dumps({
                  "online": status.players.online,
                  "max": status.players.max,
                  "sample": [p.name for p in (status.players.sample or [])],
              }))
          except Exception:
              # A server that is up as a unit but still loading its world refuses
              # the connection, which is a state to report rather than an error.
              print("null")
        '';

      # No request data reaches these; the URL selects a fixed filename.
      lifecycle = server: verb:
        script "mc-${verb}-${server}" ''
          ${pkgs.coreutils}/bin/touch ${flag server verb}
        '';

      info = server:
        script "mc-info-${server}" ''
          state="$(${systemctl} is-active ${unit server} || true)"

          # systemctl prints "[not set]" for a stopped unit rather than 0, and
          # accounting is only guaranteed while the cgroup exists.
          prop() {
            v="$(${systemctl} show ${unit server} -p "$1" --value)"
            case "$v" in ''' | "[not set]" | infinity) echo null ;; *) echo "$v" ;; esac
          }

          # Prints "null" rather than failing for a server that is not answering
          # yet, so there is no case where this turns a loading world into an
          # HTTP error.
          players=null
          if [ "$state" = active ]; then
            players="$(${lib.getExe players} ${toString minecraft.servers.${server}.port})"
            [ -n "$players" ] || players=null
          fi

          ${lib.getExe pkgs.jq} -n \
            --arg state "$state" \
            --argjson memory "$(prop MemoryCurrent)" \
            --argjson cpuNs "$(prop CPUUsageNSec)" \
            --argjson tasks "$(prop TasksCurrent)" \
            --argjson players "$players" \
            --argjson cpus "$(${pkgs.coreutils}/bin/nproc)" \
            '{$state, $memory, $cpuNs, $tasks, $players, $cpus}'
        '';

      logs = server:
        script "mc-logs-${server}" ''
          # Missing is normal: a server that has never started has no log yet.
          ${pkgs.coreutils}/bin/tail -n ${toString cfg.logLines} \
            ${logFile server} 2>/dev/null || true
        '';

      # The only hook taking input — any server command, `op` included. The
      # input is only ever passed to printf as quoted data.
      command = server:
        script "mc-cmd-${server}" ''
          # First line only. A body with embedded newlines would otherwise be
          # several console commands from one request, which is surprising in a
          # way nothing here needs.
          cmd="$(printf '%s' "''${1-}" | ${pkgs.coreutils}/bin/head -n1 | ${pkgs.coreutils}/bin/tr -d '\r')"

          if [ -z "$cmd" ]; then
            echo "nothing to send"
            exit 0
          fi

          if ! ${systemctl} is-active --quiet ${unit server}; then
            echo "server is not running"
            exit 0
          fi

          # Opening a FIFO for writing blocks until something is reading it, so
          # a server that died between the check above and here would hang this
          # request until webhook's own timeout. tee lets timeout own that.
          if printf '%s\n' "$cmd" \
            | ${pkgs.coreutils}/bin/timeout 5 ${pkgs.coreutils}/bin/tee ${fifo server} >/dev/null; then
            echo "sent"
          else
            echo "the console did not accept it"
          fi
        '';

      scripts = lib.listToAttrs (lib.concatMap (server:
        [
          (lib.nameValuePair "info-${server}" {script = info server;})
          (lib.nameValuePair "logs-${server}" {script = logs server;})
          (lib.nameValuePair "cmd-${server}" {
            script = command server;
            takesBody = true;
          })
        ]
        ++ map (verb:
          lib.nameValuePair "${verb}-${server}" {script = lifecycle server verb;})
        ["start" "stop"])
      cfg.servers);

      hooks = lib.mapAttrs (_: h:
        {
          execute-command = lib.getExe h.script;
          command-working-directory = "/tmp";
          include-command-output-in-response = true;
        }
        // lib.optionalAttrs (h.takesBody or false) {
          # Raw body, not JSON: avoids escaping disagreements with the sender.
          pass-arguments-to-command = [{source = "raw-request-body";}];
        })
      scripts;

      privilegedActions =
        lib.concatMap (server: map (verb: {inherit server verb;}) ["start" "stop"])
        cfg.servers;

      # Dashes are not legal in nginx variable names.
      mayVar = server: "mc_may_${lib.replaceStrings ["-"] ["_"] server}";

      # netbird drops labels containing commas (reverseproxy.go:934), so the
      # comma-or-end anchor is an exact membership test. `default 0` is the
      # safety property: anything unmatched is refused.
      groupMaps =
        lib.concatMapStringsSep "\n" (server: ''
          map $http_x_netbird_groups ${"$" + mayVar server} {
            default 0;
          ${lib.concatMapStringsSep "\n" (g: ''"~(^|,)${g}(,|$)" 1;'') (cfg.access.${server} or [])}
          }
        '')
        cfg.servers;

      # index.html carries no nix interpolation on purpose.
      root = pkgs.runCommand "minecraft-control-page" {} ''
        mkdir -p $out
        cp ${./_minecraft-control/index.html} $out/index.html
        cp ${pkgs.writeText "servers.json" (builtins.toJSON cfg.servers)} \
          $out/servers.json
      '';
    in {
      options.cosmos.services.minecraft.control = {
        enable = mkEnableOption "the Minecraft control web page";

        servers = mkOption {
          type = listOf str;
          default = lib.attrNames config.cosmos.services.minecraft.servers;
          defaultText = "every declared server";
          description = ''
            Servers offered on the page. Each name must match a
            `cosmos.services.minecraft.servers` entry, because it is used to
            build the unit name the path units below act on — a name here that
            is not a real server is a pair of units that control nothing.
          '';
        };

        access = mkOption {
          type = attrsOf (listOf str);
          default = lib.genAttrs cfg.servers (_: ["netbird-minecraft-control"]);
          defaultText = "every server, to netbird-minecraft-control";
          example = {
            smp = ["netbird-minecraft-smp" "netbird-minecraft-control"];
            hardcore = ["netbird-minecraft-control"];
          };
          description = ''
            Which kanidm groups may drive which server, keyed by server name.

            The names are matched against the `X-NetBird-Groups` header that
            netbird-proxy stamps on the request, which carries the caller's
            group display names straight from kanidm's `groups` claim. So a
            name here must be one of the groups
            `services/kanidm.nix` puts in that claim, or it can never match.

            A server absent from this attrset is controllable by nobody, and
            that is the intended behaviour: the nginx map backing this defaults
            to refusing, so a typo costs access rather than granting it.

            Membership is all-or-nothing per server. Someone who is not in a
            server's groups cannot read its log or its player count either — it
            is simply not their server, and the page does not show it.
          '';
        };

        proxyAddress = mkOption {
          type = str;
          example = "100.68.0.1";
          description = ''
            netbird-proxy's own mesh address, and the only source this vhost
            accepts.

            Necessary rather than defensive. The fleet runs a single All -> All
            NetBird policy, so binding to the mesh means every enrolled peer can
            reach this port — and reaching it directly skips the kanidm gate,
            which lives on gaia. It is also what makes the identity headers
            trustworthy: they are believable exactly because the one peer that
            can set them is the proxy that authenticated the user.

            NOT gaia's address. netbird-proxy enrols as its own NetBird client,
            with a WireGuard address separate from the host agent's, and dials
            upstream targets from that one. It is also absent from /api/peers,
            so the peer list does not show it and gaia's own 100.68.38.155 —
            the address in PerSourcePenaltyExemptList on this host — is the
            wrong answer, which cost a round of 403s to discover.

            Two ways to find the right one, easiest first:

              * the denial itself, in this host's nginx error log:
                `access forbidden by rule, client: <address>`
              * on gaia, nftables_state.interface_state.wg_address.IP in
                /var/lib/netbird-proxy/state.json

            Stable across reboots, that path being persisted — but it would
            change if the proxy ever re-enrolled, and the symptom of that is
            every request to this page answering 403.
          '';
        };

        logLines = mkOption {
          type = ints.positive;
          default = 300;
          description = ''
            How much of each server's `latest.log` the page shows. Raw, IP
            addresses included: a join line reads
            `Name[/1.2.3.4:5678] logged in`, so everyone who can reach this
            page can see the addresses of everyone who plays.
          '';
        };

        port = mkOption {
          type = port;
          default = 8086;
          description = ''
            The published port: nginx serves the page and proxies the API. Not
            8080 (suwayomi) or 8084 (librechat); gaia must forward this one.
          '';
        };

        webhookPort = mkOption {
          type = port;
          default = 9010;
          description = ''
            webhook's own port, bound to loopback. Never published: reaching it
            directly would be reaching the commands with no identity check at
            all, since the gate lives at the edge.
          '';
        };
      };

      config = mkIf cfg.enable {
        users.users.${user} = {
          isSystemUser = true;
          group = user;
        };
        users.groups.${user} = {};

        services.webhook = {
          enable = true;
          inherit user;
          group = user;
          ip = "127.0.0.1";
          port = cfg.webhookPort;
          inherit hooks;
        };

        systemd.tmpfiles.settings."10-minecraft-control" = {
          ${flagDir}.d = {
            inherit user;
            group = user;
            mode = "0700";
          };

          # Root-owned: the unprivileged side must not pin a server down.
          ${stateDir}.d = {
            user = "root";
            group = "root";
            mode = "0755";
          };
        };

        cosmos.system.impermanence.persist.directories = [
          {
            directory = stateDir;
            user = "root";
            group = "root";
            mode = "0755";
          }
        ];

        # The service deletes the flag first so the path unit re-arms; systemd
        # holding the path unit inactive meanwhile prevents stacked requests.
        systemd.paths = lib.listToAttrs (map ({
          server,
          verb,
        }:
          lib.nameValuePair "mc-${verb}-${server}" {
            description = "Watch for a request to ${verb} the ${server} Minecraft server";
            wantedBy = ["multi-user.target"];
            pathConfig = {
              PathExists = flag server verb;
              Unit = "mc-${verb}-${server}.service";
            };
          })
        privilegedActions);

        systemd.services =
          {
            # Broader than needed (also world data access), but the
            # alternatives — journal groups or file-based RPC — are worse.
            webhook.serviceConfig.SupplementaryGroups = ["minecraft"];
          }
          # Makes a stop outlast a deploy; also governs manual `systemctl start`.
          // lib.listToAttrs (map (server:
            lib.nameValuePair "minecraft-server-${server}" {
              unitConfig.ConditionPathExists = "!${stopped server}";
            })
          cfg.servers)
          // lib.listToAttrs (map ({
            server,
            verb,
          }:
            lib.nameValuePair "mc-${verb}-${server}" {
              description = "${verb} the ${server} Minecraft server on request";
              serviceConfig = {
                Type = "oneshot";
                ExecStartPre =
                  [
                    "${pkgs.coreutils}/bin/rm -f ${flag server verb}"
                  ]
                  # Record intent first so a crash can't lose a stop.
                  ++ (
                    if verb == "stop"
                    then ["${pkgs.coreutils}/bin/touch ${stopped server}"]
                    else ["${pkgs.coreutils}/bin/rm -f ${stopped server}"]
                  );
                ExecStart = "${systemctl} ${verb} ${unit server}";
                # Must exceed nix-minecraft's TimeoutStopSec=75s world save.
                TimeoutStartSec = 180;
              };
            })
          privilegedActions);

        services.nginx.virtualHosts."minecraft-control" = {
          listen = [
            {
              # Not loopback: netbird-proxy on gaia dials endeavour:<port>.
              addr = "0.0.0.0";
              inherit (cfg) port;
            }
          ];

          # NOT gated by the wt0 firewall: the NetBird policy is All -> All, so
          # any peer could bypass gaia's kanidm gate and spoof identity headers.
          # Literal gaia mesh address; matches PerSourcePenaltyExemptList here.
          extraConfig = ''
            allow ${cfg.proxyAddress};
            deny all;
          '';

          # Per-server authorisation is here, not in the hooks: the only path
          # to webhook, and a default-0 `map` fails closed.
          locations =
            {
              "/" = {
                inherit root;
                index = "index.html";
              };

              # Plain text, not JSON: display names may contain quotes.
              "= /whoami".extraConfig = ''
                default_type text/plain;
                return 200 "$http_x_netbird_user\n$http_x_netbird_groups\n";
              '';

              # Refuses unknown hooks; real ones match the regex locations.
              "/hooks/".extraConfig = "return 403;";
            }
            // lib.listToAttrs (map (server:
              lib.nameValuePair
              "~ ^/hooks/(info|logs|start|stop|cmd)-${server}$" {
                # No URI part: nginx forbids one in a regex location.
                proxyPass = "http://127.0.0.1:${toString cfg.webhookPort}";
                extraConfig = ''
                  if (${"$" + mayVar server} = 0) { return 403; }
                '';
              })
            cfg.servers);
        };

        # Maps must live in the http block.
        services.nginx.appendHttpConfig = groupMaps;
      };
    };
  };
}
