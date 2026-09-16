# services.suwayomi — manga server (was flake.modules.nixos.suwayomi).
{...}: {
  den.aspects.services.suwayomi.nixos = {
    config,
    lib,
    pkgs,
    ...
  }: let
    inherit (lib.options) mkEnableOption mkOption;
    inherit (lib.types) bool int port str path listOf nullOr;
    inherit (lib.lists) optional;
    inherit (lib.modules) mkIf;

    cfg = config.cosmos.services.suwayomi;

    webviewLauncher = pkgs.writeShellScript "suwayomi-server-xvfb" ''
      exec ${pkgs.xvfb-run}/bin/xvfb-run -a ${lib.getExe pkgs.suwayomi-server} "$@"
    '';
    webviewPackage = pkgs.buildFHSEnv (pkgs.appimageTools.defaultFhsEnvArgs
      // {
        name = "tachidesk-server";
        runScript = webviewLauncher;
      });
  in {
    options.cosmos.services.suwayomi = {
      ip = mkOption {
        type = str;
        # Loopback only while a local nginx vhost fronts this. Under edge
        # termination netbird-proxy dials `peer:8080` straight over the mesh
        # and a loopback bind refuses it. Reach is still firewall-governed:
        # the port opens on wt0 only (netbird.client.exposedPorts on
        # endeavour).
        default =
          if config.cosmos.networking.edgeTerminated
          then "0.0.0.0"
          else "127.0.0.1";
        defaultText = "127.0.0.1, or 0.0.0.0 when the edge terminates elsewhere";
      };
      port = mkOption {
        type = port;
        default = 8080;
      };
      dataDir = mkOption {
        type = path;
        default = "/var/lib/suwayomi-server";
      };
      downloadsDir = mkOption {
        type = nullOr path;
        default = null;
      };
      homeLink = mkOption {
        type = nullOr path;
        default = null;
      };
      extensionStores = mkOption {
        type = listOf str;
        # index.pb, not the old index.min.json: keiyoushi moved to Mihon's
        # store and left the old URL serving a two-entry "Outdated App" stub
        # — the page looked broken while the server rendered what it was
        # given. Needs suwayomi-server >= 2.3.2223 (extension API v1.6),
        # hence the pin ahead of nixpkgs in modules/pkgs/suwayomi-server.nix.
        #
        # Named for the server.conf key 2.3 renamed from extensionRepos —
        # which the nixpkgs module still writes; 2.3 migrates that to an empty
        # list rather than erroring, so the page looks exactly as broken.
        # Hence the explicit settings.server.extensionStores below.
        default = ["https://raw.githubusercontent.com/keiyoushi/extensions/repo/index.pb"];
      };
      expose = mkOption {
        type = bool;
        default = false;
      };
      openFirewall = mkOption {
        type = bool;
        default = false;
      };
      flareSolverrUrl = mkOption {
        type = nullOr str;
        default = null;
        example = "http://127.0.0.1:8191";
        description = ''
          Where to reach a FlareSolverr instance, or null to go without.

          This is how Cloudflare-protected sources are read. Without it such a
          source raises "IOException: Cloudflare bypass currently disabled" on
          every request and the manga shows zero chapters — indistinguishable in
          the UI from the series genuinely having none, which is worth knowing
          before debugging the wrong thing.

          Pair with den.aspects.services.flaresolverr on the same host.
        '';
      };

      basicAuth = {
        enable = mkEnableOption "HTTP basic authentication for the web UI";
        username = mkOption {
          type = str;
          default = config.cosmos.user.name;
        };
      };
      webview.enable = mkEnableOption "the embedded Chromium WebView (KCEF)" // {default = false;};

      downloadRetry = {
        enable =
          mkEnableOption ''
            a timer that revives chapter downloads killed by HTTP 429
          ''
          // {default = false;};
        interval = mkOption {
          type = str;
          default = "2min";
          description = "How long between sweeps of the download queue.";
        };
        maxResets = mkOption {
          type = int;
          default = 20;
          description = ''
            Stop resetting a chapter after this many sweeps, so one that can
            never finish — pulled upstream, say — is not cycled forever. It
            stays in the queue as ERROR for you to look at.
          '';
        };
      };
    };

    config = {
      assertions = [
        {
          assertion = cfg.homeLink != null -> cfg.downloadsDir != null;
          message = "cosmos.services.suwayomi.homeLink requires downloadsDir to be set.";
        }
      ];

      sops.secrets."keys/suwayomi/basic-auth-password" = mkIf cfg.basicAuth.enable {
        owner = "suwayomi";
      };

      cosmos.system.impermanence.persist.directories =
        [
          {
            directory = cfg.dataDir;
            user = "suwayomi";
            group = "suwayomi";
            mode = "0700";
          }
        ]
        ++ optional (cfg.downloadsDir != null) {
          directory = cfg.downloadsDir;
          user = "suwayomi";
          group = "suwayomi";
          mode = "0750";
        };

      cosmos.user.extraGroups = optional (cfg.downloadsDir != null) "suwayomi";

      systemd.tmpfiles.rules =
        optional (cfg.homeLink != null)
        "L+ ${cfg.homeLink} - - - - ${cfg.downloadsDir}";

      # Comick's CDN answers page bursts with HTTP 429 regardless of pacing;
      # the downloader gives up after three tries and parks the chapter as
      # ERROR. startDownloader does not revive those — it skips entries at
      # tries=3, and re-enqueueing in place increments the count and zeroes
      # progress. Only a dequeue resets the counter, so this sweeps ERROR
      # entries out and puts them back. It converges because fetched pages
      # stay in the on-disk cache: each sweep resumes rather than restarts.
      systemd.services.suwayomi-download-retry = mkIf cfg.downloadRetry.enable {
        description = "Re-queue suwayomi chapter downloads that failed on HTTP 429";
        after = ["suwayomi-server.service"];
        path = [pkgs.curl pkgs.jq pkgs.gawk];
        serviceConfig = {
          Type = "oneshot";
          User = "suwayomi";
          Group = "suwayomi";
        };
        script = ''
          set -euo pipefail

          state="${cfg.dataDir}/download-retry.state"
          api="http://127.0.0.1:${toString cfg.port}/api/graphql"
          auth=()
          ${lib.optionalString cfg.basicAuth.enable ''
            auth=(--user "${cfg.basicAuth.username}:$(cat ${config.sops.secrets."keys/suwayomi/basic-auth-password".path})")
          ''}

          gql() {
            curl -sf "''${auth[@]}" "$api" \
              -H 'Content-Type: application/json' --data-binary "$1"
          }

          # A server that is still starting is not an error worth reporting.
          queue=$(gql '{"query":"{ downloadStatus { queue { chapter { id } state } } }"}') || exit 0
          failed=$(printf '%s' "$queue" |
            jq -r '.data.downloadStatus.queue[]? | select(.state == "ERROR") | .chapter.id')
          [ -n "$failed" ] || exit 0

          touch "$state"
          next=""
          retry=""
          for id in $failed; do
            n=$(awk -v i="$id" '$1 == i { print $2 }' "$state")
            n=''${n:-0}
            if [ "$n" -ge ${toString cfg.downloadRetry.maxResets} ]; then
              echo "chapter $id has failed $n sweeps; leaving it alone"
              next="$next$id $n"$'\n'
              continue
            fi
            next="$next$id $((n + 1))"$'\n'
            if [ -z "$retry" ]; then retry="$id"; else retry="$retry,$id"; fi
          done
          printf '%s' "$next" > "$state"
          [ -n "$retry" ] || exit 0

          gql "{\"query\":\"mutation { dequeueChapterDownloads(input:{ids:[$retry]}) { clientMutationId } }\"}" > /dev/null
          gql "{\"query\":\"mutation { enqueueChapterDownloads(input:{ids:[$retry]}) { clientMutationId } }\"}" > /dev/null
          echo "re-queued chapter(s): $retry"
        '';
      };

      systemd.timers.suwayomi-download-retry = mkIf cfg.downloadRetry.enable {
        wantedBy = ["timers.target"];
        timerConfig = {
          OnBootSec = "5min";
          OnUnitActiveSec = cfg.downloadRetry.interval;
        };
      };

      systemd.services.suwayomi-server = {
        preStart = ''
          mkdir -p ${cfg.dataDir}/.local/share/Tachidesk
        '';
        environment.JAVA_TOOL_OPTIONS = "-Xverify:none";
      };

      users.users.suwayomi.extraGroups = mkIf cfg.webview.enable ["video" "render"];

      services.suwayomi-server = {
        enable = true;
        inherit (cfg) dataDir openFirewall;
        package = mkIf cfg.webview.enable webviewPackage;

        settings.server = {
          inherit (cfg) ip port;

          # The 2.3 key, written directly: the module's extensionRepos option
          # targets the 2.1 name, which 2.3 silently discards. The basicAuth*
          # keys below stay on the module options on purpose — 2.3 migrates
          # those, and the module envsubsts basicAuthPasswordFile so the
          # secret never enters the store.
          extensionStores = cfg.extensionStores;

          # Follows webview.enable, which until now it did not: that option
          # only swapped the *package*; whether CEF starts at all is this
          # runtime setting, which defaults to true. With the webview off the
          # server still initialised CEF outside the FHS env —
          # UnsatisfiedLinkError plus a 519 MB Chromium re-download into the
          # state directory, every start.
          kcefEnabled = cfg.webview.enable;

          # Cloudflare. mkIf rather than an explicit false, so a host that sets
          # no URL leaves suwayomi's own default alone.
          flareSolverrEnabled = mkIf (cfg.flareSolverrUrl != null) true;
          flareSolverrUrl = mkIf (cfg.flareSolverrUrl != null) cfg.flareSolverrUrl;
          downloadAsCbz = true;
          downloadsPath = mkIf (cfg.downloadsDir != null) cfg.downloadsDir;
          basicAuthEnabled = cfg.basicAuth.enable;
          basicAuthUsername = mkIf cfg.basicAuth.enable cfg.basicAuth.username;
          basicAuthPasswordFile =
            mkIf cfg.basicAuth.enable
            config.sops.secrets."keys/suwayomi/basic-auth-password".path;
        };
      };

      # Dropped when the edge terminates TLS.
      services.nginx.virtualHosts = mkIf (cfg.expose && !config.cosmos.networking.edgeTerminated) {
        "suwayomi.lvdar.nl" = {
          forceSSL = true;
          enableACME = false;
          sslCertificate = "/var/lib/acme/lvdar.nl/fullchain.pem";
          sslCertificateKey = "/var/lib/acme/lvdar.nl/key.pem";
          locations."/" = {
            recommendedProxySettings = true;
            proxyWebsockets = true;
            proxyPass = "http://127.0.0.1:${toString cfg.port}";
          };
        };
      };
    };
  };
}
