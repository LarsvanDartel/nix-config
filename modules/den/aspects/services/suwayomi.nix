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
        default = "127.0.0.1";
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
      extensionRepos = mkOption {
        type = listOf str;
        default = ["https://raw.githubusercontent.com/keiyoushi/extensions/repo/index.min.json"];
      };
      expose = mkOption {
        type = bool;
        default = false;
      };
      openFirewall = mkOption {
        type = bool;
        default = false;
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
          inherit (cfg) ip port extensionRepos;
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
