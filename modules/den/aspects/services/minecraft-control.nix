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
#     its API are one origin and the whole thing is one port to publish.
#   * sudo grants the webhook user exactly six commands. polkit would be the
#     conventional answer and is not available: security.polkit.enable is false
#     on these headless hosts, which is the same wall services/crowdsec.nix hit.
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
      sudo = "/run/wrappers/bin/sudo";

      unit = server: "minecraft-server-${server}.service";

      # One script per server per action, generated rather than parameterised.
      #
      # This is the whole security argument: no request data reaches a shell.
      # webhook maps a URL to a fixed argv with no arguments at all, so there is
      # no server name to validate, no quoting to get wrong, and no way to ask
      # for a unit that is not in this list.
      action = server: verb: let
        privileged =
          if verb == "status"
          then "${systemctl} is-active ${unit server}"
          else "${sudo} -n ${systemctl} ${verb} ${unit server}";
      in
        pkgs.writeShellApplication {
          name = "mc-${verb}-${server}";
          text = ''
            # is-active exits non-zero for a stopped unit, which is information
            # rather than failure — webhook would otherwise turn a stopped
            # server into an HTTP error.
            ${privileged} || true
          '';
        };

      actions = ["start" "stop" "status"];

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

      page = pkgs.writeText "index.html" ''
        <!doctype html>
        <meta charset="utf-8">
        <meta name="viewport" content="width=device-width,initial-scale=1">
        <title>Minecraft</title>
        <style>
          :root { color-scheme: dark }
          body { font: 16px/1.5 system-ui, sans-serif; max-width: 34rem;
                 margin: 3rem auto; padding: 0 1rem;
                 background: #16161d; color: #d8d8e0 }
          h1 { font-size: 1.25rem; font-weight: 600 }
          .s { border: 1px solid #2c2c38; border-radius: .5rem;
               padding: 1rem; margin: 1rem 0 }
          .n { font-weight: 600; display: flex; justify-content: space-between;
               align-items: center }
          .t { font-size: .8rem; padding: .15rem .5rem; border-radius: 1rem;
               background: #2c2c38; color: #9a9aa8 }
          .up { background: #1d3a24; color: #7fd18f }
          .dn { background: #3a1d1d; color: #d18f8f }
          button { font: inherit; padding: .4rem 1rem; margin: .75rem .5rem 0 0;
                   border: 1px solid #2c2c38; border-radius: .375rem;
                   background: #22222c; color: inherit; cursor: pointer }
          button:hover:not(:disabled) { background: #2c2c38 }
          button:disabled { opacity: .5; cursor: default }
        </style>
        <h1>Minecraft servers</h1>
        <div id="servers"></div>
        <script>
          const servers = ${builtins.toJSON cfg.servers};
          const el = document.getElementById("servers");

          async function hook(name) {
            const r = await fetch("hooks/" + name, { method: "POST" });
            return (await r.text()).trim();
          }

          async function refresh(name) {
            const tag = document.getElementById("t-" + name);
            const state = await hook("status-" + name);
            const up = state === "active";
            tag.textContent = up ? "running" : state || "stopped";
            tag.className = "t " + (up ? "up" : "dn");
          }

          async function act(name, verb) {
            const bs = document.querySelectorAll("button[data-s=" + name + "]");
            bs.forEach(b => b.disabled = true);
            document.getElementById("t-" + name).textContent = verb + "ing…";
            await hook(verb + "-" + name);
            // Starting is not instant; poll until it settles.
            for (let i = 0; i < 20; i++) {
              await new Promise(r => setTimeout(r, 1500));
              await refresh(name);
              const t = document.getElementById("t-" + name).textContent;
              if (t === "running" || t === "stopped" || t === "inactive") break;
            }
            bs.forEach(b => b.disabled = false);
          }

          for (const s of servers) {
            const d = document.createElement("div");
            d.className = "s";
            d.innerHTML =
              '<div class="n"><span>' + s + '</span>' +
              '<span class="t" id="t-' + s + '">…</span></div>' +
              '<button data-s="' + s + '" data-v="start">Start</button>' +
              '<button data-s="' + s + '" data-v="stop">Stop</button>';
            el.appendChild(d);
            refresh(s);
          }
          el.addEventListener("click", e => {
            const b = e.target.closest("button");
            if (b) act(b.dataset.s, b.dataset.v);
          });
        </script>
      '';

      root = pkgs.runCommand "minecraft-control-page" {} ''
        mkdir -p $out
        cp ${page} $out/index.html
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

        # Exactly these commands, no arguments accepted, no password. The unit
        # names are baked in from `servers`, so this grants control of the
        # Minecraft servers and provably nothing else on the host.
        security.sudo.extraRules = [
          {
            users = [user];
            commands = lib.concatMap (server:
              map (verb: {
                command = "${systemctl} ${verb} ${unit server}";
                options = ["NOPASSWD" "SETENV"];
              }) ["start" "stop"])
            cfg.servers;
          }
        ];

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
