# services.arr.lingarr — machine-translates subtitles via OpenRouter.
# Settings below are written into lingarr's database on every start; UI edits revert on restart.
{den, ...}: {
  den.aspects.services.arr.lingarr = {
    includes = [den.aspects.services.arr];
    nixos = {
      config,
      lib,
      pkgs,
      ...
    }: let
      inherit (lib.options) mkOption mkPackageOption;
      inherit (lib.types) port path bool str listOf submodule ints;
      inherit (lib.modules) mkIf;

      cfg-arr = config.cosmos.services.arr;
      cfg = cfg-arr.lingarr;

      language = submodule {
        options = {
          name = mkOption {type = str;};
          code = mkOption {type = str;};
        };
      };

      arrs = {
        SONARR = config.services.sonarr;
        RADARR = config.services.radarr;
      };

      # Upstream hardcodes /app/Statics; provided by a namespace bind, not a source patch.
      appDir = "${cfg.package}/lib/lingarr";
    in {
      options.cosmos.services.arr.lingarr = {
        package = mkPackageOption pkgs "lingarr" {};
        port = mkOption {
          type = port;
          default = 9876;
        };
        stateDir = mkOption {
          type = path;
          default = "${cfg-arr.stateDir}/lingarr";
        };
        openFirewall = mkOption {
          type = bool;
          default = true;
        };
        user = mkOption {
          type = str;
          default = "lingarr";
        };
        model = mkOption {
          type = str;
          description = "OpenRouter model id. Any chat model works; pricing is per token.";
          default = "anthropic/claude-haiku-5.5";
        };
        maxConcurrentJobs = mkOption {
          type = ints.positive;
          # Hangfire workers across all queues, so media syncs share these slots.
          default = 4;
        };
        sourceLanguages = mkOption {
          type = listOf language;
          default = [
            {
              name = "English";
              code = "en";
            }
          ];
        };
        targetLanguages = mkOption {
          type = listOf language;
          default = [
            {
              name = "Dutch";
              code = "nl";
            }
          ];
        };
      };

      config = {
        systemd.tmpfiles.rules = ["d '${cfg.stateDir}' 0700 ${cfg.user} root - -"];
        users.users.${cfg.user} = {
          isSystemUser = true;
          group = "media";
        };

        sops.secrets."keys/openrouter/api-key" = {};

        systemd.services.lingarr = {
          description = "lingarr";
          after = ["network-online.target" "sonarr.service" "radarr.service"];
          wants = ["network-online.target"];
          wantedBy = ["multi-user.target"];

          environment = {
            ASPNETCORE_URLS = "http://0.0.0.0:${toString cfg.port}";
            DB_CONNECTION = "sqlite";
            SQLITE_DB_PATH = "${cfg.stateDir}/local.db";
            DB_HANGFIRE_SQLITE_PATH = "${cfg.stateDir}/Hangfire.db";
            ENCRYPTION_KEYS = "${cfg.stateDir}/keys";
            TELEMETRY_ENABLED = "false";
            MAX_CONCURRENT_JOBS = toString cfg.maxConcurrentJobs;

            # "localai" = upstream's generic OpenAI-compatible client.
            SERVICE_TYPE = builtins.toJSON ["localai"];
            LOCAL_AI_ENDPOINT = "https://openrouter.ai/api/v1/chat/completions";
            LOCAL_AI_MODEL = cfg.model;
            LOCAL_AI_API_KEY_FILE = "%d/openrouter";

            SOURCE_LANGUAGES = builtins.toJSON cfg.sourceLanguages;
            TARGET_LANGUAGES = builtins.toJSON cfg.targetLanguages;

            SONARR_URL = "http://127.0.0.1:${toString arrs.SONARR.settings.server.port}";
            SONARR_API_KEY_FILE = "%t/lingarr/sonarr";
            RADARR_URL = "http://127.0.0.1:${toString arrs.RADARR.settings.server.port}";
            RADARR_API_KEY_FILE = "%t/lingarr/radarr";
          };

          serviceConfig = {
            Type = "simple";
            User = cfg.user;
            Group = "media";
            SyslogIdentifier = "lingarr";
            # ASP.NET resolves wwwroot relative to the working directory.
            WorkingDirectory = appDir;
            RuntimeDirectory = "lingarr";
            RuntimeDirectoryMode = "0700";
            LoadCredential = ["openrouter:${config.sops.secrets."keys/openrouter/api-key".path}"];
            TemporaryFileSystem = "/app";
            BindReadOnlyPaths = ["${appDir}/Statics:/app/Statics"];

            ExecStartPre = "+${pkgs.writeShellScript "lingarr-arr-keys" (lib.concatStrings (lib.mapAttrsToList (name: arr: ''
                key=$(${lib.getExe pkgs.xmlstarlet} sel -t -v /Config/ApiKey '${arr.dataDir}/config.xml')
                install -m 0400 -o ${cfg.user} /dev/null "$RUNTIME_DIRECTORY/${lib.toLower name}"
                printf '%s' "$key" > "$RUNTIME_DIRECTORY/${lib.toLower name}"
              '')
              arrs))}";
            ExecStart = lib.getExe cfg.package;
            Restart = "on-failure";
          };
        };

        networking.firewall = mkIf cfg.openFirewall {allowedTCPPorts = [cfg.port];};
      };
    };
  };
}
