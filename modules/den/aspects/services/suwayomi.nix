# services.suwayomi — manga server (was flake.modules.nixos.suwayomi).
{...}: {
  den.aspects.services.suwayomi.nixos = {
    config,
    lib,
    pkgs,
    ...
  }: let
    inherit (lib.options) mkEnableOption mkOption;
    inherit (lib.types) bool port str path listOf nullOr;
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

          This is how Cloudflare-protected sources are read now. The
          alternative is suwayomi's embedded Chromium (see webview.enable),
          which on 2.3 fails to link against glib inside the FHS wrapper and
          crashloops the whole server rather than just failing the bypass. Out
          of process, a browser crash costs one chapter fetch.

          Without it, a protected source raises
          "IOException: Cloudflare bypass currently disabled" on every request
          and the manga shows zero chapters — which looks exactly like the
          series having no chapters, so it is worth knowing the difference.

          Pair with den.aspects.services.flaresolverr on the same host; see
          hosts/endeavour.nix.
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

          # Cloudflare. mkIf rather than writing false explicitly, so a host
          # that has not set a URL leaves suwayomi's own default alone.
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
