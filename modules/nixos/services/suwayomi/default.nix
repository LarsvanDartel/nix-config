{
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

  # KCEF (the embedded Chromium powering the WebView / Cloudflare bypass)
  # downloads a prebuilt libcef.so and a jcef_helper subprocess at runtime.
  # These are linked against the standard FHS loader and a pile of X11/GTK/GL
  # libraries that don't exist on NixOS, so loading them throws
  # UnsatisfiedLinkError. Run the whole server inside an FHS sandbox that
  # provides the Chromium runtime closure (appimageTools ships exactly that).
  #
  # CEF also insists on an X11 display even for offscreen rendering, so launch
  # the server under a headless Xvfb (KCEF gives no way to pass --headless).
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
    enable = mkEnableOption "suwayomi manga server";

    ip = mkOption {
      type = str;
      default = "127.0.0.1";
      description = "Address Suwayomi binds to. Keep on loopback when reverse-proxied or local-only.";
    };

    port = mkOption {
      type = port;
      default = 8080;
      description = "Suwayomi web-UI port.";
    };

    dataDir = mkOption {
      type = path;
      default = "/var/lib/suwayomi-server";
      description = "Directory in which Suwayomi stores its data and downloaded scans.";
    };

    downloadsDir = mkOption {
      type = nullOr path;
      default = null;
      example = "/var/lib/suwayomi-downloads";
      description = ''
        Override the directory Suwayomi downloads chapters into. Unlike the
        default location under dataDir (which is private to the suwayomi user),
        this directory is created group-readable via the suwayomi group and the
        primary user is added to it, so the downloads can be linked into a home
        directory (see homeLink).
      '';
    };

    homeLink = mkOption {
      type = nullOr path;
      default = null;
      example = "/home/lvdar/manga";
      description = ''
        If set, create a symlink at this path pointing to downloadsDir. Requires
        downloadsDir to be set.
      '';
    };

    extensionRepos = mkOption {
      type = listOf str;
      default = [
        "https://raw.githubusercontent.com/keiyoushi/extensions/repo/index.min.json"
      ];
      description = "Extension repositories made available for installation in the UI.";
    };

    expose = mkOption {
      type = bool;
      default = false;
      description = "Expose the web UI at suwayomi.lvdar.nl via nginx.";
    };

    openFirewall = mkOption {
      type = bool;
      default = false;
      description = "Open the firewall for the configured port (for direct LAN access).";
    };

    basicAuth = {
      enable = mkEnableOption "HTTP basic authentication for the web UI";

      username = mkOption {
        type = str;
        default = config.cosmos.user.name;
        description = "Basic auth username.";
      };
    };

    webview.enable =
      mkEnableOption ''
        the embedded Chromium WebView (KCEF) for sources that need a
        Cloudflare/JS bypass. Runs the server inside an FHS sandbox''
      // {default = false;};
  };

  config = mkIf cfg.enable {
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
        # Group-readable so the primary user (added to the suwayomi group) can
        # browse the downloads through homeLink.
        mode = "0750";
      };

    # Let the primary user read the downloads via the suwayomi group.
    cosmos.user.extraGroups = optional (cfg.downloadsDir != null) "suwayomi";

    # Persisted symlink from the user's home to the downloads directory. tmpfiles
    # recreates it on every boot, so it survives impermanence wipes.
    systemd.tmpfiles.rules =
      optional (cfg.homeLink != null)
      "L+ ${cfg.homeLink} - - - - ${cfg.downloadsDir}";

    systemd.services.suwayomi-server = {
      # The upstream tmpfiles rule that creates this directory races with the
      # impermanence bind-mount of dataDir, leaving envsubst unable to write
      # server.conf. Recreate it in preStart, which runs after the mount is up.
      preStart = ''
        mkdir -p ${cfg.dataDir}/.local/share/Tachidesk
      '';

      # Extensions are loaded by converting Android .dex -> .jar at runtime; the
      # result lacks StackMapTable frames, so the JDK 21 bytecode verifier
      # rejects them (VerifyError: Expecting a stackmap frame). Disable the
      # verifier for this JVM. The launcher hardcodes its java args, but the JVM
      # reads JAVA_TOOL_OPTIONS automatically.
      environment.JAVA_TOOL_OPTIONS = "-Xverify:none";
    };

    # KCEF uses offscreen GL; let it reach the GPU (falls back to software).
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

    services.nginx.virtualHosts = mkIf cfg.expose {
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
}
