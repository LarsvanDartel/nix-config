# services.minecraft.control — a web page for starting and stopping the
# Minecraft servers, for people who are not administrators of this host.
#
# The problem this solves is narrow and the shape follows from it. Players want
# a server up; the person who can currently do that is whoever has root on
# endeavour. Everything else here is about granting exactly that and nothing
# adjacent.
#
# Deliberately NOT a server panel. nixpkgs has no Crafty/MCSManager/Pterodactyl,
# and the one general-purpose thing it does have — cockpit — is a full systems
# administration console with a terminal in it. Handing that to somebody so they
# can restart a survival world is not a smaller grant than root, it *is* root
# with extra steps.
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
#   * a systemd path unit per action carries the privilege. The unprivileged
#     side can only create one specific empty file; a root oneshot watching for
#     it runs the one command it exists to run.
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
      inherit (lib.types) listOf port str;
      inherit (lib.modules) mkIf;

      cfg = config.cosmos.services.minecraft.control;

      user = "minecraft-control";
      systemctl = "/run/current-system/sw/bin/systemctl";

      unit = server: "minecraft-server-${server}.service";

      # Where the unprivileged half drops its request. tmpfs, so a pending flag
      # never survives a reboot into an action nobody asked for any more.
      flagDir = "/run/minecraft-control";
      flag = server: verb: "${flagDir}/${verb}-${server}";

      # One script per server per action, generated rather than parameterised.
      #
      # This is the whole security argument: no request data reaches a shell.
      # webhook maps a URL to a fixed argv with no arguments at all, so there is
      # no server name to validate, no quoting to get wrong, and no way to ask
      # for a unit that is not in this list.
      action = server: verb: let
        body =
          if verb == "status"
          # is-active needs no privilege, so it stays a direct call.
          then "${systemctl} is-active ${unit server}"
          # Everything the unprivileged side can express: this filename exists,
          # or it does not. The matching path unit turns that into the command.
          else "${pkgs.coreutils}/bin/touch ${flag server verb}";
      in
        pkgs.writeShellApplication {
          name = "mc-${verb}-${server}";
          text = ''
            # is-active exits non-zero for a stopped unit, which is information
            # rather than failure — webhook would otherwise turn a stopped
            # server into an HTTP error.
            ${body} || true
          '';
        };

      actions = ["start" "stop" "status"];

      # start/stop only: status is not privileged and has no unit.
      privilegedActions =
        lib.concatMap (server: map (verb: {inherit server verb;}) ["start" "stop"])
        cfg.servers;

      scripts = lib.listToAttrs (lib.concatMap (server:
        map (verb:
          lib.nameValuePair "${verb}-${server}" (action server verb))
        actions)
      cfg.servers);

      # Keyed by hook id — the attribute name becomes the id and the URL, so
      # `start-smp` is served at /hooks/start-smp.
      hooks =
        lib.mapAttrs (_: script: {
          execute-command = lib.getExe script;
          command-working-directory = "/tmp";
          include-command-output-in-response = true;
        })
        scripts;

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
        enable = mkEnableOption "the Minecraft start/stop web page";

        servers = mkOption {
          type = listOf str;
          default = lib.attrNames config.cosmos.services.minecraft.servers;
          defaultText = "every declared server";
          description = ''
            Servers offered on the page. Each name must match a
            `cosmos.services.minecraft.servers` entry, because it is used to
            build the unit name granted in the sudo rule below — a name here
            that is not a real server is a rule that grants nothing.
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

        systemd.services = lib.listToAttrs (map ({
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
              # `endeavour:<port>` and a loopback socket refuses that. Reach is
              # governed by the firewall, which opens this on the NetBird
              # interface only — see exposedPorts on the host.
              addr = "0.0.0.0";
              inherit (cfg) port;
            }
          ];

          locations."/" = {
            inherit root;
            index = "index.html";
          };

          # Same origin as the page, so the fetch() calls above need no CORS
          # and no second published port.
          locations."/hooks/".proxyPass = "http://127.0.0.1:${toString cfg.webhookPort}/hooks/";
        };
      };
    };
  };
}
