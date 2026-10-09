# services.ollama — local LLM inference on endeavour's Tesla P100.
{den, ...}: {
  den.aspects.services.ollama.nixos = {
    config,
    lib,
    pkgs,
    ...
  }: let
    inherit (lib.options) mkOption;
    inherit (lib.types) bool listOf port str;

    cfg = config.cosmos.services.ollama;
  in {
    options.cosmos.services.ollama = {
      port = mkOption {
        type = port;
        default = 11434;
        description = "Ollama's HTTP API port. Upstream's default.";
      };

      modelsDir = mkOption {
        type = str;
        example = "/srv/ollama/models";
        description = ''
          Where the weights live. On /tank because they are tens of gigabytes
          and the system SSD has ~144 G free against the pool's 1.4 T.

          Deliberately absent from restic and sanoid: every byte is a
          re-download from ollama's library, which is the same call the arr
          suite's downloads got. Backing up 23 G of reproducible weights would
          crowd out the paths that are genuinely irreplaceable.
        '';
      };

      models = mkOption {
        type = listOf str;
        default = [];
        description = ''
          Pulled once, in the background, after the service starts. Not synced
          — `syncModels` stays off so anything pulled by hand (`ollama pull`
          over SSH) is not deleted on the next activation.
        '';
      };

      keepAlive = mkOption {
        type = str;
        default = "60m";
        description = ''
          How long a model stays resident in VRAM after its last request.

          Raised from upstream's 5m once the cost of a cold load was measured
          here: 199s for llama3.1:8b and 105s for a 14B, because the weights
          come off the spinning array rather than an SSD. At 5m, stepping away
          for a coffee means waiting two to three minutes for the first token,
          which reads as broken rather than slow.

          Cheaper than it sounds. The card was measured idling at 40 W holding
          259 MiB, and holding weights in VRAM adds almost nothing to that —
          the power goes on computing, not on storing. The real cost is space:
          a resident 14B occupies ~9 GB of the 16 GB, so a second large model
          will evict the first rather than sit alongside it.
        '';
      };

      meshExposed = mkOption {
        type = bool;
        default = false;
        description = ''
          Bind the API on the mesh rather than loopback, so other peers can
          use it directly.

          Off by default, and that is a security decision rather than a
          conservative one: ollama's API has no authentication whatsoever, so
          this hands every peer unmetered use of the GPU and of any model
          loaded. LibreChat reaches it over loopback and does not need this.

          Binding is only half of it — the port also has to appear in
          `cosmos.services.netbird.client.exposedPorts` on the host, which is
          what actually opens the mesh interface. Same split as suwayomi.
        '';
      };
    };

    config = {
      services.ollama = {
        enable = true;

        # nixpkgs builds CUDA for Turing+; the P100 (sm_60) gets no kernel and
        # ollama silently falls back to CPU. Per-package, not global
        # cudaCapabilities (shared nixpkgs). CUDA 13 drops Pascal: keep _12.
        package = pkgs.ollama-cuda.override {
          cudaArches = ["sm_60"];
          cudaPackages = pkgs.cudaPackages_12;
        };

        inherit (cfg) port;
        modelsDir = cfg.modelsDir;
        loadModels = cfg.models;

        syncModels = false;

        host =
          if cfg.meshExposed
          then "0.0.0.0"
          else "127.0.0.1";

        environmentVariables.OLLAMA_KEEP_ALIVE = cfg.keepAlive;
      };

      # Static user: DynamicUser's shifting UID loses ownership of /tank/ollama
      # across reboots, leaving ollama unable to read its own models.
      users.users.ollama = {
        isSystemUser = true;
        group = "ollama";
        home = "/var/lib/ollama";
      };
      users.groups.ollama = {};

      systemd.services.ollama.serviceConfig = {
        DynamicUser = lib.mkForce false;
        User = "ollama";
        Group = "ollama";
        ReadWritePaths = [cfg.modelsDir];
      };

      systemd.tmpfiles.rules = [
        "d /tank/ollama 0750 ollama ollama - -"
        "d ${cfg.modelsDir} 0750 ollama ollama - -"
      ];
    };
  };

  # services.ollama.librechat — LibreChat, browser front end for ollama and OpenRouter.
  # The first OIDC login becomes the ADMIN account.
  den.aspects.services.ollama.librechat = {
    includes = [den.aspects.services.ollama den.aspects.core.sops];

    nixos = {
      config,
      lib,
      ...
    }: let
      inherit (lib.options) mkOption;
      inherit (lib.types) port str;

      cfg = config.cosmos.services.ollama.librechat;
      ollamaCfg = config.cosmos.services.ollama;
    in {
      options.cosmos.services.ollama.librechat = {
        port = mkOption {
          type = port;
          default = 8084;
          description = ''
            Open WebUI's port, kept on purpose: gaia forwards chat.lvdar.nl
            to endeavour:8084 and the netbird exposedPorts list names it, so
            keeping it means the publish path survives the switch untouched.
            Not upstream's 3080, and not 8080 — suwayomi holds that on this
            host, and two services binding one port is an activation failure
            that rolls the whole deploy back.
          '';
        };

        domain = mkOption {
          type = str;
          default = "chat.lvdar.nl";
          description = ''
            Public name. Feeds DOMAIN_SERVER (the OIDC redirect is built from
            it), DOMAIN_CLIENT, and the kanidm originUrl — all of which must
            match what kanidm has registered exactly. A mismatch is rejected
            at the callback, after a successful login, which reads like a bug
            in the IdP rather than a typo in a URL.
          '';
        };
      };

      config = {
        services.librechat = {
          enable = true;

          enableLocalDB = true;

          env = {
            PORT = cfg.port;

            # Edge-terminated: netbird-proxy dials across the mesh.
            HOST =
              if config.cosmos.networking.edgeTerminated
              then "0.0.0.0"
              else "127.0.0.1";

            DOMAIN_SERVER = "https://${cfg.domain}";
            DOMAIN_CLIENT = "https://${cfg.domain}";

            # Only kills email signup; OIDC logins still auto-provision.
            ALLOW_REGISTRATION = false;

            ALLOW_SOCIAL_LOGIN = true;

            OPENID_CLIENT_ID = "librechat";
            OPENID_ISSUER = "https://auth.lvdar.nl/oauth2/openid/librechat";
            OPENID_SCOPE = "openid profile email";
            OPENID_BUTTON_LABEL = "kanidm";

            # No code default: unset yields redirect_uri ".../chat.lvdar.nlundefined".
            # Must match the kanidm originUrl exactly.
            OPENID_CALLBACK_URL = "/oauth/openid/callback";

            OPENID_USE_PKCE = true;
          };

          # Via systemd LoadCredential, read as root.
          credentials = {
            CREDS_KEY = config.sops.secrets."keys/librechat/creds-key".path;
            CREDS_IV = config.sops.secrets."keys/librechat/creds-iv".path;
            JWT_SECRET = config.sops.secrets."keys/librechat/jwt-secret".path;
            JWT_REFRESH_SECRET = config.sops.secrets."keys/librechat/jwt-refresh-secret".path;
            OPENID_SESSION_SECRET = config.sops.secrets."keys/librechat/session-secret".path;

            # Shared with the kanidm provisioner, which owns the sops file.
            OPENID_CLIENT_SECRET = config.sops.secrets."keys/librechat/oauth-client-secret".path;
            OPENROUTER_KEY = config.sops.secrets."keys/openrouter/api-key".path;
          };

          settings = {
            version = "1.2.1";

            endpoints.custom = [
              # ollama ignores the API key; an empty `default` crashes the
              # service at start (Zod), so seed one even with fetch.
              {
                name = "Ollama";
                apiKey = "ollama";
                baseURL = "http://127.0.0.1:${toString ollamaCfg.port}/v1";
                models = {
                  default =
                    if ollamaCfg.models != []
                    then ollamaCfg.models
                    else ["llama3.2"];
                  fetch = true;
                };
              }
              {
                name = "OpenRouter";
                apiKey = "\${OPENROUTER_KEY}";
                baseURL = "https://openrouter.ai/api/v1";
                models = {
                  default = ["meta-llama/llama-3-70b-instruct"];
                  fetch = true;
                };
              }
            ];
          };
        };

        # Upstream doesn't order after network: OIDC discovery can race the
        # resolver and silently disable login until restart (observed).
        systemd.services.librechat = {
          after = ["network-online.target"];
          wants = ["network-online.target"];
        };

        sops.secrets = {
          "keys/librechat/creds-key" = {};
          "keys/librechat/creds-iv" = {};
          "keys/librechat/jwt-secret" = {};
          "keys/librechat/jwt-refresh-secret" = {};
          "keys/librechat/session-secret" = {};
          "keys/openrouter/api-key" = {};
          "keys/librechat/oauth-client-secret".owner = "kanidm";
        };

        cosmos.system.impermanence.persist.directories = [
          {
            directory = config.services.librechat.dataDir;
            user = "librechat";
            group = "librechat";
            mode = "0750";
          }
          {
            # /var/db, not /var/lib.
            directory = config.services.mongodb.dbpath;
            user = "mongodb";
            group = "mongodb";
            mode = "0750";
          }
        ];

        services.kanidm.provision = {
          groups.librechat-users = {
            overwriteMembers = false;
            members = ["lvdar"];
          };

          systems.oauth2.librechat = {
            displayName = "LibreChat";
            basicSecretFile = config.sops.secrets."keys/librechat/oauth-client-secret".path;
            originUrl = "https://${cfg.domain}/oauth/openid/callback";
            originLanding = "https://${cfg.domain}";
            scopeMaps.librechat-users = ["openid" "email" "profile"];

            preferShortUsername = true;
          };
        };
      };
    };
  };
}
