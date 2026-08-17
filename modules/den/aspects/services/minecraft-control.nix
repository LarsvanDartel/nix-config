# services.minecraft.control — a web page for running the Minecraft servers,
# for people who are not administrators of this host: start and stop, who is
# online, the console, the log, and what each server is costing in memory and
# CPU.
#
# It began as start/stop alone and the shape still shows that: the two commands
# that need root go through a path unit that never sees input, while everything
# added since is either a plain read or a line written to the server's own
# console FIFO. Worth keeping in mind when adding to it — reaching for root is
# almost never the answer, because nix-minecraft already exposes the console and
# the log to group `minecraft`.
#
# Still not a general server panel: nixpkgs has no Crafty/MCSManager/
# Pterodactyl, and the one general-purpose thing it does have — cockpit — is a
# systems administration console with a terminal in it. Handing that to somebody
# so they can restart a survival world is not a smaller grant than root, it *is*
# root with extra steps. What this does hand out is bounded by two things: the
# five commands per server below, and the game's own authority model.
#
# The console is the part to think twice about. It takes arbitrary input and
# passes it to the server, so anyone who reaches this page can `op` themselves,
# `ban` anyone, or `stop` the server — membership of the gating kanidm group is
# server administration, not merely the power to restart. That is the intended
# grant here and it is why the group exists separately from every other one.
#
# Three pieces, each doing one thing:
#
#   * webhook (nixpkgs' own) turns an HTTP request into one fixed command. It is
#     bound to loopback and never reached directly.
#   * nginx serves a static page and proxies /hooks to webhook, so the page and
#     its API are one origin and the whole thing is one port to publish. The
#     page itself lives in _minecraft-control/index.html — underscored so
#     import-tree leaves the directory alone, as with every other _-prefixed
#     path here.
#   * a systemd path unit per lifecycle action carries the privilege. The
#     unprivileged side can only create one specific empty file; a root oneshot
#     watching for it runs the one command it exists to run. Only start and stop
#     need this — see SupplementaryGroups below for how the rest gets its
#     access, and why it is not root.
#
# That last piece was sudo first and could not work. roles/server.nix sets
# security.sudo.execWheelOnly, so the wrapper is mode 4550 root:wheel and a
# non-wheel user is refused at exec — before any rule is consulted, and with
# "Permission denied" rather than anything about permissions policy. Putting
# this user in wheel to reach a six-command rule is a far larger grant than the
# rule withholds. polkit is the conventional answer and is unavailable:
# security.polkit.enable is false on headless hosts, the same wall
# services/crowdsec.nix hit.
#
# The path units end up being the better boundary anyway. There is no setuid
# binary, nothing parses an argument, and the privileged half never sees input
# at all — it is triggered by the *existence* of a filename fixed at build time.
#
# Authentication is not implemented here, on purpose. gaia publishes this
# *gated*, so netbird-proxy demands a NetBird identity, NetBird fills its groups
# from kanidm's `groups` claim, and kanidm decides membership — the mechanism
# services/kanidm.nix already drives through `gatedServices`. Adding a person is
# a group membership in kanidm and nothing else; there is no account, password
# or session in this aspect at all.
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

      # nix-minecraft's systemd-socket console, chosen in services/minecraft.nix
      # over tmux. Mode 0660 minecraft:minecraft, so writing to it is what the
      # SupplementaryGroups grant below is for. RCON is not an option here and
      # deliberately so — that file explains why.
      fifo = server: "/run/minecraft/${server}.stdin";

      # The server's own log rather than the journal. Both exist (that is the
      # point of the systemd-socket choice), but the journal is readable only by
      # systemd-journal/adm, and joining this user to either would hand it every
      # service's log on the host to show a Minecraft one.
      logFile = server: "${minecraft.dataDir}/${server}/logs/latest.log";

      # Where the unprivileged half drops its request. tmpfs, so a pending flag
      # never survives a reboot into an action nobody asked for any more.
      flagDir = "/run/minecraft-control";
      flag = server: verb: "${flagDir}/${verb}-${server}";

      script = name: text: pkgs.writeShellApplication {inherit name text;};

      # start/stop: the two that need root, and the only two that still go
      # through a path unit. No request data reaches these at all — the URL
      # selects a filename fixed at build time, and that is the whole grant.
      lifecycle = server: verb:
        script "mc-${verb}-${server}" ''
          ${pkgs.coreutils}/bin/touch ${flag server verb}
        '';

      # Everything the page polls, in one request. Four round trips per server
      # per tick is what this replaces, and they were never independently
      # useful: the player count is meaningless without knowing the unit is up.
      info = server:
        script "mc-info-${server}" ''
          state="$(${systemctl} is-active ${unit server} || true)"

          # systemctl prints "[not set]" for a stopped unit rather than 0, and
          # accounting is only guaranteed while the cgroup exists.
          prop() {
            v="$(${systemctl} show ${unit server} -p "$1" --value)"
            case "$v" in ''' | "[not set]" | infinity) echo null ;; *) echo "$v" ;; esac
          }

          # mcstatus never throws: it reports {"online": false, "error": ...}
          # for a refused connection, which is exactly the state of a server
          # that is up as a unit but still loading its world. The timeout is
          # for the other case — a server wedged badly enough to accept the
          # TCP connection and then never answer the status ping.
          players=null
          if [ "$state" = active ]; then
            players="$(${lib.getExe' pkgs.mcstatus "mcstatus"} \
              127.0.0.1:${toString minecraft.servers.${server}.port} json 2>/dev/null \
              | ${lib.getExe pkgs.jq} -c '.status.players // null' || echo null)"
            [ -n "$players" ] || players=null
          fi

          ${lib.getExe pkgs.jq} -n \
            --arg state "$state" \
            --argjson memory "$(prop MemoryCurrent)" \
            --argjson cpuNs "$(prop CPUUsageNSec)" \
            --argjson tasks "$(prop TasksCurrent)" \
            --argjson players "$players" \
            '{$state, $memory, $cpuNs, $tasks, $players}'
        '';

      logs = server:
        script "mc-logs-${server}" ''
          # Missing is normal: a server that has never started has no log yet.
          ${pkgs.coreutils}/bin/tail -n ${toString cfg.logLines} \
            ${logFile server} 2>/dev/null || true
        '';

      # The console. Unlike every other hook here this one takes input, and it
      # is the reason this page is a bigger grant than start/stop: whoever
      # reaches it can run any command the server accepts, `op` and `stop`
      # included. That is a deliberate choice — see the option description.
      #
      # The input never reaches a shell as code. writeShellApplication runs
      # under `set -euo pipefail`, "$1" is quoted, and printf writes it as data.
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

      # Hook id -> { script, whether it takes the request body }. The id becomes
      # the URL, so `start-smp` is served at /hooks/start-smp.
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
          # The POST body verbatim as $1 — not a JSON field, because a console
          # line is text and wrapping it in JSON only adds a parse that can
          # disagree with the sender about escaping.
          pass-arguments-to-command = [{source = "raw-request-body";}];
        })
      scripts;

      # start/stop only: the rest are reads or go through the FIFO.
      privilegedActions =
        lib.concatMap (server: map (verb: {inherit server verb;}) ["start" "stop"])
        cfg.servers;

      # One nginx variable per server, holding 1 when the caller's groups admit
      # them. Dashes are not legal in an nginx variable name.
      mayVar = server: "mc_may_${lib.replaceStrings ["-"] ["_"] server}";

      # X-NetBird-Groups is a comma-separated list of group *display names* —
      # exactly the netbird-* names kanidm puts in the `groups` claim. netbird
      # drops any label containing a comma before joining (reverseproxy.go:934),
      # so anchoring on comma-or-end is an exact membership test rather than a
      # substring one: netbird-minecraft-smp2 cannot match netbird-minecraft-smp.
      #
      # `default 0` is the entire safety property. A server with no groups
      # listed, a request that arrived without the header, a name nobody has —
      # all of them land on 0 and are refused.
      groupMaps =
        lib.concatMapStringsSep "\n" (server: ''
          map $http_x_netbird_groups ${"$" + mayVar server} {
            default 0;
          ${lib.concatMapStringsSep "\n" (g: ''"~(^|,)${g}(,|$)" 1;'') (cfg.access.${server} or [])}
          }
        '')
        cfg.servers;

      # The page and its data, kept apart on purpose: index.html carries no
      # nix interpolation at all, so it stays a file a browser can open and a
      # linter can read, and changing the server list never touches it.
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
          default = "100.68.38.155";
          description = ''
            gaia's NetBird address, and the only source this vhost accepts.

            Necessary rather than defensive. The fleet runs a single All -> All
            NetBird policy, so binding to the mesh means every enrolled peer can
            reach this port — and reaching it directly skips the kanidm gate,
            which lives on gaia. It is also what makes the identity headers
            trustworthy: they are believable exactly because the one peer that
            can set them is the proxy that authenticated the user.
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
            8080 (suwayomi) or 8084 (open-webui); gaia must forward this one.
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

        # The console and the log both live behind group `minecraft`: the FIFO
        # is 0660 minecraft:minecraft and latest.log is 0660 under a 0770 data
        # directory. This is the one grant in this aspect that is broader than
        # the thing it enables — it also means read and write access to the
        # world data on disk.
        #
        # Taken deliberately rather than built around, because the alternative
        # is worse in both directions. Reaching the journal instead would need
        # systemd-journal or adm, which is *every* service's log on this host.
        # Routing reads through the root path units too would mean a
        # request/response protocol over files for what is a `tail` — more
        # moving parts guarding a smaller gap, since a full console can already
        # `stop` the server and `op` anyone.
        # The drop box. Only this user may create anything in it, and the only
        # names that mean anything are the ones a path unit below watches for.
        systemd.tmpfiles.settings."10-minecraft-control".${flagDir}.d = {
          inherit user;
          group = user;
          mode = "0700";
        };

        # The privilege boundary, one pair of units per action.
        #
        # The path unit fires on the file existing and starts the service; the
        # service deletes the flag first, so the path unit re-arms instead of
        # looping on a file that is still there. systemd holds the path unit
        # inactive while the service runs, which is also what keeps a
        # double-click from stacking two `systemctl stop`s.
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
            # The console and the log both live behind group `minecraft`: the
            # FIFO is 0660 minecraft:minecraft and latest.log is 0660 under a
            # 0770 data directory. This is the one grant in this aspect that is
            # broader than the thing it enables — it also carries read and write
            # access to the world data on disk.
            #
            # Taken deliberately rather than built around, because both
            # alternatives are worse. Reading the journal instead would need
            # systemd-journal or adm, which is *every* service's log on this
            # host. Routing the reads through the root path units below would
            # mean a request/response protocol over files to run a `tail` —
            # more moving parts guarding a smaller gap, given a full console can
            # already `stop` the server and `op` anyone.
            webhook.serviceConfig.SupplementaryGroups = ["minecraft"];
          }
          // lib.listToAttrs (map ({
            server,
            verb,
          }:
            lib.nameValuePair "mc-${verb}-${server}" {
              description = "${verb} the ${server} Minecraft server on request";
              serviceConfig = {
                Type = "oneshot";
                ExecStartPre = "${pkgs.coreutils}/bin/rm -f ${flag server verb}";
                # The entire grant. No argument reaches this from anywhere.
                ExecStart = "${systemctl} ${verb} ${unit server}";
                # Blocking is deliberate — systemd keeps the path unit inactive
                # while this runs, which is what stops a double click stacking two
                # of these. But nix-minecraft gives the server TimeoutStopSec=75s
                # to save its world, and the default 90s here leaves almost no
                # margin over that; a slow save would land as a failed unit.
                TimeoutStartSec = 180;
              };
            })
          privilegedActions);

        services.nginx.virtualHosts."minecraft-control" = {
          listen = [
            {
              # The mesh, not loopback: netbird-proxy on gaia dials
              # `endeavour:<port>` and a loopback socket refuses that.
              addr = "0.0.0.0";
              inherit (cfg) port;
            }
          ];

          # The firewall opening this on wt0 alone is NOT a gate. The fleet runs
          # one NetBird policy — All -> All, every protocol, bidirectional — so
          # "reachable on the mesh" means reachable by every enrolled peer, and
          # for a while that is exactly what this page was: anyone with a peer
          # could skip gaia, call /hooks/stop-smp directly and never meet the
          # kanidm gate at all.
          #
          # Pinning the source to gaia's mesh address is what makes the gate the
          # only way in, and it is also what makes the identity headers below
          # mean anything: they are trustworthy precisely because the only peer
          # that can set them is the proxy that authenticates the user.
          #
          # A literal for the same reason every other cross-host value here is
          # one — den cannot read gaia's config. It matches the address in
          # PerSourcePenaltyExemptList on this host.
          extraConfig = ''
            allow ${cfg.proxyAddress};
            deny all;
          '';

          # Same origin as the page, so the fetch() calls above need no CORS
          # and no second published port.
          #
          # Per-server authorisation lives here rather than in the hooks: this
          # is the only path to webhook, which binds loopback, and a `map` that
          # defaults to 0 fails closed in a way a shell test repeated in ten
          # scripts does not.
          locations =
            {
              "/" = {
                inherit root;
                index = "index.html";
              };

              # Who the gate says you are. Plain text rather than JSON because a
              # display name may legally contain a quote — netbird only
              # guarantees printable ASCII — and assembling JSON from it in an
              # nginx string would let that break the document.
              "= /whoami".extraConfig = ''
                default_type text/plain;
                return 200 "$http_x_netbird_user\n$http_x_netbird_groups\n";
              '';

              # The catch-all, and it refuses. Every real hook is matched by a
              # regex location below, which nginx prefers over this prefix; what
              # lands here is a hook for a server that is not in `servers`, or a
              # name that does not exist. Neither should reach webhook.
              "/hooks/".extraConfig = "return 403;";
            }
            // lib.listToAttrs (map (server:
              lib.nameValuePair
              "~ ^/hooks/(info|logs|start|stop|cmd)-${server}$" {
                # No URI part: nginx forbids one in a regex location, and the
                # path wants passing through unchanged anyway.
                proxyPass = "http://127.0.0.1:${toString cfg.webhookPort}";
                extraConfig = ''
                  if (${"$" + mayVar server} = 0) { return 403; }
                '';
              })
            cfg.servers);
        };

        # The maps have to live in the http block, not the server block.
        services.nginx.appendHttpConfig = groupMaps;
      };
    };
  };
}
