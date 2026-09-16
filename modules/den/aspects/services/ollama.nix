# services.ollama — local LLM inference on endeavour's Tesla P100.
#
# Gives the idle P100 a job (jellyfin transcodes on the Arc A310; nothing
# else here speaks CUDA). HBM2's 732 GB/s makes token generation strong for
# a 2016 card; no tensor cores or flash-attention (Ampere and later) makes
# prompt processing comparatively slow — good generation, mediocre ingest.
# The whole point of this file is the `cudaArches` override below.
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

        # The reason this file exists. nixpkgs builds CUDA for Turing+;
        # the P100 is 6.0, so stock ollama-cuda contains no kernel this GPU
        # can run. The failure mode is the dangerous kind: ollama does not
        # error, it silently falls back to CPU — tokens still appear, just
        # slowly. Check `nvidia-smi` during generation before believing it.
        #
        # Per-package, not `nixpkgs.config.cudaCapabilities`: this repo
        # shares one nixpkgs instance across all four hosts, and the global
        # knob would invalidate the CUDA closure fleet-wide to fix one card.
        # cudaPackages_12 is pinned deliberately — CUDA 13 drops Pascal, so
        # the day the default moves this breaks with a compiler error that
        # never names this GPU.
        package = pkgs.ollama-cuda.override {
          cudaArches = ["sm_60"];
          cudaPackages = pkgs.cudaPackages_12;
        };

        inherit (cfg) port;
        modelsDir = cfg.modelsDir;
        loadModels = cfg.models;

        # See the option description: pulling by hand is a normal thing to
        # do, and syncing would undo it on next activation.
        syncModels = false;

        # Loopback unless asked otherwise. LibreChat is co-located and talks
        # over localhost, so the API needs no wider reach to be useful.
        host =
          if cfg.meshExposed
          then "0.0.0.0"
          else "127.0.0.1";

        environmentVariables.OLLAMA_KEEP_ALIVE = cfg.keepAlive;
      };

      # The nixpkgs DynamicUser + StateDirectory trap (see attic.nix,
      # prometheus.nix, crowdsec.nix), here via its second consequence: a
      # dynamic UID means ownership of /tank/ollama changes across a reboot,
      # and ollama cannot read the models it downloaded itself.
      # /var/lib/ollama stays ephemeral on purpose — a generated keypair;
      # weights are on /tank, chats live in LibreChat's MongoDB.
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
        # ProtectSystem = strict is inherited from upstream, so the pool path
        # has to be named explicitly or the download fails read-only.
        ReadWritePaths = [cfg.modelsDir];
      };

      systemd.tmpfiles.rules = [
        "d /tank/ollama 0750 ollama ollama - -"
        "d ${cfg.modelsDir} 0750 ollama ollama - -"
      ];
    };
  };

  # services.ollama.librechat — LibreChat, the browser front end for the
  # engine above and, via OpenRouter, the one cloud provider this fleet
  # admits. Replaced Open WebUI for OpenRouter access and agent features;
  # unlike every authlib client here its OIDC library sends a PKCE code
  # challenge, so it needs no allowInsecureClientDisablePkce concession.
  #
  # Knowingly given up: Open WebUI's built-in RAG (LibreChat's is an
  # unpackaged rag_api + pgvector pair) and its model-management UI (pulls
  # happen via cosmos.services.ollama.models or SSH). The admin panel is
  # likewise unpackaged — the first OIDC login becomes the ADMIN account,
  # all a single-user deployment needs. A sub-aspect like tangled.spindle:
  # useless without its parent, which is fine alone.
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

          # MongoDB on this host: loopback, unauthenticated (the module wires
          # MONGO_URI itself). The database holds the chats and the accounts,
          # so it is persisted below and backed up in endeavour.nix.
          enableLocalDB = true;

          env = {
            PORT = cfg.port;

            # Loopback would be right if a local nginx fronted this; under
            # edge termination netbird-proxy dials across the mesh and a
            # loopback socket refuses it. Same as services/suwayomi.nix.
            HOST =
              if config.cosmos.networking.edgeTerminated
              then "0.0.0.0"
              else "127.0.0.1";

            # The public origin on both sides: DOMAIN_SERVER builds the OIDC
            # redirect, DOMAIN_CLIENT is what the SPA calls.
            DOMAIN_SERVER = "https://${cfg.domain}";
            DOMAIN_CLIENT = "https://${cfg.domain}";

            # kanidm is the only way in. OIDC logins auto-provision users
            # and are not gated by this flag — this kills email signup, which
            # would need SMTP this host does not have anyway. The first OIDC
            # login creates the ADMIN account. A broken OIDC setup would mean
            # no way in at all, but kanidm OIDC is proven on half this fleet.
            ALLOW_REGISTRATION = false;

            # The login button stays hidden without this even when the
            # OPENID_* variables are complete.
            ALLOW_SOCIAL_LOGIN = true;

            OPENID_CLIENT_ID = "librechat";
            OPENID_ISSUER = "https://auth.lvdar.nl/oauth2/openid/librechat";
            OPENID_SCOPE = "openid profile email";
            OPENID_BUTTON_LABEL = "kanidm";

            # No code-level default despite the .env.example showing one —
            # openidStrategy.js does `DOMAIN_SERVER + OPENID_CALLBACK_URL`
            # with no `||` fallback, so leaving this unset sends kanidm a
            # redirect_uri of literally "https://chat.lvdar.nlundefined" and
            # every login fails with invalid_origin. Must match the kanidm
            # originUrl below exactly.
            OPENID_CALLBACK_URL = "/oauth/openid/callback";

            # The reason no concession appears in the kanidm block below:
            # LibreChat's openid-client strategy sends the code challenge,
            # unlike the authlib clients (jellyfin, traccar, tino) that each
            # had to disarm kanidm's PKCE requirement.
            OPENID_USE_PKCE = true;
          };

          # Via systemd LoadCredential: the unit's script cats these into
          # the environment at start, so the librechat user never owns a
          # sops file and no template is needed (open-webui needed one
          # because its service user read the env file itself).
          credentials = {
            # LibreChat's own crypto, generated once (`openssl rand -hex`)
            # and parked in nix-secrets: the CREDS pair encrypts stored
            # provider keys, the JWT pair signs sessions, the session secret
            # signs the OIDC state cookie.
            CREDS_KEY = config.sops.secrets."keys/librechat/creds-key".path;
            CREDS_IV = config.sops.secrets."keys/librechat/creds-iv".path;
            JWT_SECRET = config.sops.secrets."keys/librechat/jwt-secret".path;
            JWT_REFRESH_SECRET = config.sops.secrets."keys/librechat/jwt-refresh-secret".path;
            OPENID_SESSION_SECRET = config.sops.secrets."keys/librechat/session-secret".path;

            # The same value kanidm provisions as the client secret — one
            # secret, two readers, no conflict: LoadCredential reads as root,
            # and the kanidm provisioner gets its own owner below.
            OPENID_CLIENT_SECRET = config.sops.secrets."keys/librechat/oauth-client-secret".path;
            OPENROUTER_KEY = config.sops.secrets."keys/openrouter/api-key".path;
          };

          # librechat.yaml, re-read on every start — no Open WebUI-style
          # ENABLE_PERSISTENT_CONFIG trap where settings migrate into the
          # database on first boot.
          settings = {
            version = "1.2.1";

            endpoints.custom = [
              # The local engine via its OpenAI-compatible /v1. LibreChat
              # 0.8.0 has no `noApiKey`; ollama ignores the Authorization
              # header entirely, so a dummy satisfies the schema. `fetch`
              # populates the picker from the engine's /models — but an empty
              # `default` still crashes the service at start (Zod: "Array
              # must contain at least 1 element"), so it needs a real seed
              # even though fetch immediately replaces it.
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

            # titleConvo off on both endpoints on purpose: titles are still
            # made, client-side from the first message, at no model-call
            # cost. Enabling it buys back Open WebUI's extra call per
            # conversation; on OpenRouter it is cheap enough to flip some day.
          };
        };

        # The nixpkgs module orders librechat only after tmpfiles/mongodb,
        # not the network — its OIDC discovery request at startup can race
        # a not-yet-ready resolver and lose, silently disabling login until
        # the next restart with no retry. Observed once, live, on this exact
        # deploy.
        systemd.services.librechat = {
          after = ["network-online.target"];
          wants = ["network-online.target"];
        };

        # Every key `credentials` reads must be declared for sops-nix to
        # decrypt it. Root ownership is enough for all of them — only
        # LoadCredential, running as root, reads these files.
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
            # Uploads and logs. The nixpkgs module runs as a plain declared
            # user (no DynamicUser), so the uid-pinning gymnastics open-webui
            # needed do not apply here.
            directory = config.services.librechat.dataDir;
            user = "librechat";
            group = "librechat";
            mode = "0750";
          }
          {
            # MongoDB's data. Note the path is upstream's own default,
            # /var/db, not /var/lib — the distinction RESTORE.md's list has
            # to keep straight.
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

            # Without this the OIDC `preferred_username` is the full SPN
            # (lvdar@auth.lvdar.nl), which becomes the display name.
            preferShortUsername = true;
          };
        };
      };
    };
  };
}
