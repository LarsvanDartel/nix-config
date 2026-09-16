# services.ollama — local LLM inference on endeavour's Tesla P100.
#
# The card was already in this host and had never had a job: jellyfin
# transcodes on the Arc A310 (`renderD128`) and nothing else here speaks CUDA,
# so `nvidia-smi` reported 0 MiB used and 0% utilisation indefinitely. This is
# what gives it one.
#
# A P100 is a better inference card than its 2016 date suggests, for one
# reason: token generation is bound by memory bandwidth, and HBM2 gives this
# 732 GB/s — more than most cards you could buy new today. What it does not
# have is tensor cores or flash-attention (Ampere and later), so prompt
# processing is comparatively slow. Expect good generation, mediocre ingest.
#
# The whole point of this file is the `cudaArches` override below. Everything
# else is the usual nixpkgs-module unwiring.
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

        # The reason this file exists.
        #
        # nixpkgs builds CUDA for `cudaCapabilities`, which is currently
        # ["7.5" "8.0" "8.6" "8.9" "9.0" "10.0" "10.3" "12.0" "12.1"] — Turing
        # and newer. A P100 is compute capability 6.0, below every entry, so a
        # stock `ollama-cuda` contains no kernel this GPU can execute.
        #
        # The failure mode is the dangerous kind: ollama does not error, it
        # quietly falls back to CPU. Tokens still appear, just slowly, so
        # everything looks like it works and the GPU stays at 0 MiB. Check
        # `nvidia-smi` during generation before believing any of this.
        #
        # Overridden per-package rather than through
        # `nixpkgs.config.cudaCapabilities`, which would be the obvious global
        # knob and is the wrong one here: this repo shares a single nixpkgs
        # instance across all four hosts, so setting it there invalidates the
        # CUDA closure fleet-wide to fix one card in one machine.
        #
        # cudaPackages_12 is pinned, not incidental. CUDA 13 removes Pascal
        # support entirely and nixpkgs already carries cudaPackages_13, so the
        # day the default moves this breaks — with a compiler error about an
        # unsupported architecture rather than anything naming this GPU.
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

      # The same nixpkgs trap attic.nix, prometheus.nix and crowdsec.nix each
      # document: the module sets DynamicUser = true *and* StateDirectory, so
      # systemd insists on managing state under /var/lib/private. Here it is
      # the second consequence that bites rather than the EBUSY one — a
      # dynamic UID means the ownership of /tank/ollama changes out from under
      # the weights across a reboot, and ollama then cannot read models it
      # downloaded itself.
      #
      # /var/lib/ollama is left ephemeral on purpose. It holds a generated
      # keypair and nothing else of value; the models are on /tank and the
      # chats live in LibreChat's MongoDB.
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
  # engine above and, through OpenRouter, the one cloud provider this fleet
  # admits. It replaced Open WebUI here: the point of the switch is OpenRouter
  # access and LibreChat's agent features, and unlike every authlib client in
  # this fleet its OIDC library sends a PKCE code challenge, so it is the one
  # oauth2 client that needs no allowInsecureClientDisablePkce concession.
  #
  # What the switch gives up, knowingly: Open WebUI's built-in knowledge/RAG
  # (LibreChat's RAG is a separate rag_api + pgvector pair nixpkgs does not
  # package), and its model-management UI (LibreChat only lists what the
  # engine has; pulls happen through cosmos.services.ollama.models or SSH).
  # The admin panel is likewise unpackaged — the first OIDC login becomes the
  # ADMIN account, which is all a single-user deployment needs.
  #
  # A sub-aspect for the same reason tangled.spindle is one: it is useless
  # without its parent and always wants it (the local endpoint is half the
  # point), but the parent is perfectly useful alone (a mesh-exposed API with
  # no UI is a reasonable thing to run).
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

            # Loopback would be right if a local nginx fronted this. Under edge
            # termination netbird-proxy dials `endeavour:8084` across the mesh
            # and a loopback socket refuses it — the same reasoning, and the
            # same expression, as services/suwayomi.nix.
            HOST =
              if config.cosmos.networking.edgeTerminated
              then "0.0.0.0"
              else "127.0.0.1";

            # The public origin on both sides: DOMAIN_SERVER builds the OIDC
            # redirect, DOMAIN_CLIENT is what the SPA calls.
            DOMAIN_SERVER = "https://${cfg.domain}";
            DOMAIN_CLIENT = "https://${cfg.domain}";

            # kanidm is the only way in. OIDC logins auto-provision their
            # users and are not gated by this flag (only the yaml
            # `registration.allowedDomains` list could gate them, and it is
            # unset) — this kills email signup, which would need SMTP this
            # host does not have anyway. The first OIDC login creates the
            # ADMIN account. A broken OIDC setup would mean no way in at all,
            # but kanidm OIDC is proven on half this fleet and the fix is a
            # rebuild away.
            ALLOW_REGISTRATION = false;

            # The login button stays hidden without this even when the
            # OPENID_* variables are complete.
            ALLOW_SOCIAL_LOGIN = true;

            OPENID_CLIENT_ID = "librechat";
            OPENID_ISSUER = "https://auth.lvdar.nl/oauth2/openid/librechat";
            OPENID_SCOPE = "openid profile email";
            OPENID_BUTTON_LABEL = "kanidm";

            # The reason no concession appears in the kanidm block below:
            # LibreChat's openid-client strategy sends the code challenge,
            # unlike the authlib clients (jellyfin, traccar, tino) that each
            # had to disarm kanidm's PKCE requirement.
            OPENID_USE_PKCE = true;
          };

          # Delivered via systemd LoadCredential: the unit's script cats each
          # of these into the environment at start, so the librechat user
          # never needs to own a sops file and no template is needed
          # (open-webui needed one because its service user read the env file
          # itself).
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

          # librechat.yaml. Everything here is re-read on every start —
          # LibreChat has no equivalent of Open WebUI's ENABLE_PERSISTENT_CONFIG
          # trap, where settings migrate into the database on first boot and
          # the environment stops mattering.
          settings = {
            version = "1.2.1";

            endpoints.custom = [
              # The local engine, spoken to through its OpenAI-compatible /v1.
              # LibreChat 0.8.0 has no `noApiKey`, but ollama ignores the
              # Authorization header entirely, so a dummy satisfies the
              # schema. `fetch` populates the model picker from the engine's
              # /models — the same list cosmos.services.ollama.models pulls.
              {
                name = "Ollama";
                apiKey = "ollama";
                baseURL = "http://127.0.0.1:${toString ollamaCfg.port}/v1";
                models = {
                  default = [];
                  fetch = true;
                };
              }
              {
                name = "OpenRouter";
                apiKey = "\${OPENROUTER_KEY}";
                baseURL = "https://openrouter.ai/api/v1";
                models = {
                  default = [];
                  fetch = true;
                };
              }
            ];

            # titleConvo is left off on both endpoints on purpose. Titles are
            # how a conversation is findable later, and LibreChat still makes
            # them — client-side, from the first message, at no model-call
            # cost. Enabling titleConvo here would buy back Open WebUI's
            # behaviour (an extra call per conversation) on endpoints where
            # that wait is felt; on OpenRouter it is cheap enough to be worth
            # flipping some day.
          };
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
