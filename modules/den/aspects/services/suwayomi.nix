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
        # Loopback is right only while a local nginx vhost fronts this. Under
        # edge termination netbird-proxy dials `peer:8080` straight over the
        # mesh, and a loopback-bound socket refuses that connection — the app
        # has to answer on the netbird interface itself. Reach is still
        # governed by the firewall, which opens this port on wt0 only (see
        # cosmos.services.netbird.client.exposedPorts on endeavour).
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
        # index.pb, not the index.min.json this used to point at. keiyoushi
        # moved to Mihon's Extension Store and left the old URL serving a
        # two-entry stub that reads "Outdated App" / "Update to Mihon 0.20.1+" —
        # so the page looked broken while the server was faithfully rendering
        # everything it had been given. Needs suwayomi-server >= 2.3.2223 for
        # extension API v1.6, which is why modules/pkgs/suwayomi-server.nix
        # pins ahead of nixpkgs.
        #
        # Named for the *server.conf* key, which 2.3 renamed from
        # extensionRepos to extensionStores. That rename is not cosmetic: the
        # nixpkgs module still writes the old key, 2.3's migration of it yields
        # an empty list rather than an error, and the extension page then looks
        # exactly as broken as it did before the upgrade. Hence the explicit
        # settings.server.extensionStores below rather than the module option.
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

      # Comick's image CDN answers a burst of page requests with HTTP 429, and
      # not on a rate you can pace around — a plain sequential fetch with a
      # second between pages still trips it intermittently. The reader survives
      # that because a failed page gets a retry button; the downloader gives up
      # after three tries and parks the chapter as ERROR.
      #
      # startDownloader does not revive those: an entry already at tries=3 is
      # skipped and the queue goes straight back to STOPPED. Re-enqueueing it
      # where it sits is worse than useless — it increments the try count
      # instead of clearing it and zeroes the progress. Only a dequeue resets
      # the counter, so this sweeps ERROR entries out and puts them back.
      #
      # It converges because the pages already fetched stay in the on-disk
      # cache: measured over one sweep, two chapters went 22% -> 61% and
      # 10% -> 84%, and both finished on the next. So each pass resumes rather
      # than restarting, and a chapter completes after a few sweeps.
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

          # The 2.3 key. Written directly because the nixpkgs module's
          # extensionRepos option targets the 2.1 name, which 2.3 silently
          # discards. The basicAuth* keys below are left on the module options
          # on purpose — 2.3 does migrate those to authMode/authUsername, and
          # the module turns basicAuthPasswordFile into an envsubst placeholder
          # so the secret never enters the store. Hand-writing them would lose
          # that.
          extensionStores = cfg.extensionStores;

          # Follows webview.enable, which until now it did not. That option only
          # swapped the *package* for the FHS-wrapped one; whether the server
          # tries to start CEF at all is this runtime setting, and it defaults
          # to true. So with the webview off, suwayomi still initialised CEF on
          # every start — outside the FHS env, where it cannot resolve glib —
          # logged an UnsatisfiedLinkError, and re-downloaded 519 MB of Chromium
          # into the state directory to do it. Harmless but entirely wasted.
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
