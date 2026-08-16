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
        default = "/tank/ollama/models";
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
          — `syncModels` stays off so anything pulled by hand from the web UI
          is not deleted on the next activation.
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
          loaded. The web UI reaches it over loopback and does not need this.

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

        # See the option description: pulling by hand from the web UI is a
        # normal thing to do, and syncing would undo it on next activation.
        syncModels = false;

        # Loopback unless asked otherwise. The web UI is co-located and talks
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
      # chats belong to the web UI.
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

  # services.ollama.webui — Open WebUI, the browser front end for the engine
  # above. A sub-aspect for the same reason tangled.spindle is one: it is
  # useless without its parent and always wants it, but the parent is perfectly
  # useful alone (a mesh-exposed API with no UI is a reasonable thing to run).
  den.aspects.services.ollama.webui = {
    includes = [den.aspects.services.ollama den.aspects.core.sops];

    nixos = {
      config,
      lib,
      ...
    }: let
      inherit (lib.options) mkOption;
      inherit (lib.types) port str;

      cfg = config.cosmos.services.ollama.webui;
      ollamaCfg = config.cosmos.services.ollama;
    in {
      options.cosmos.services.ollama.webui = {
        port = mkOption {
          type = port;
          default = 8084;
          description = ''
            Not upstream's 8080 — suwayomi already holds that on endeavour, and
            two services binding the same port is an activation failure that
            rolls the whole deploy back.
          '';
        };

        domain = mkOption {
          type = str;
          default = "chat.lvdar.nl";
          description = ''
            Public name. Used for the OIDC redirect URI and WEBUI_URL, both of
            which must match what kanidm has registered exactly — a mismatch
            here is rejected at the callback, after a successful login, which
            reads like a bug in the IdP rather than a typo in a URL.
          '';
        };
      };

      config = {
        services.open-webui = {
          enable = true;
          inherit (cfg) port;

          # Loopback would be right if a local nginx fronted this. Under edge
          # termination netbird-proxy dials `endeavour:8084` across the mesh
          # and a loopback socket refuses it — the same reasoning, and the same
          # expression, as services/suwayomi.nix.
          host =
            if config.cosmos.networking.edgeTerminated
            then "0.0.0.0"
            else "127.0.0.1";

          environment = {
            # Upstream's telemetry defaults, restated because setting
            # `environment` at all replaces the module's default attrset.
            SCARF_NO_ANALYTICS = "True";
            DO_NOT_TRACK = "True";
            ANONYMIZED_TELEMETRY = "False";

            # The engine is on this host; no reason to cross the mesh.
            OLLAMA_BASE_URL = "http://127.0.0.1:${toString ollamaCfg.port}";

            # Must be the public origin rather than the listen address: it is
            # what the OIDC redirect is built from.
            WEBUI_URL = "https://${cfg.domain}";

            ENABLE_OAUTH_SIGNUP = "True";
            OAUTH_PROVIDER_NAME = "kanidm";
            OAUTH_CLIENT_ID = "open-webui";
            OAUTH_SCOPES = "openid email profile";
            OPENID_PROVIDER_URL = "https://auth.lvdar.nl/oauth2/openid/open-webui/.well-known/openid-configuration";

            # ENABLE_LOGIN_FORM is deliberately left at its default. Turning
            # the local form off is the tidy end state, but doing it before the
            # OIDC round trip is proven leaves no way in at all — the first
            # account also has to exist before it can be made an admin.

            # Everything below this line is a PersistentConfig setting, and
            # this is the switch that makes any of it take effect.
            #
            # Open WebUI copies each such variable into a `config` table in its
            # database on first boot and reads the *database* from then on. So
            # the settings below, added to a deployment that has already run
            # once, would do exactly nothing — the values are already in the DB
            # and win. There is no error; the flags simply have no effect,
            # which is a deeply confusing thing to debug.
            #
            # False makes the environment authoritative on every start, which
            # is what this repo wants anyway: settings in git, surviving a
            # rollback and a reinstall. The cost is real and worth stating —
            # changes made in the admin UI no longer persist across a restart,
            # so anything that matters has to be written here instead.
            ENABLE_PERSISTENT_CONFIG = "False";

            # The reason this block exists.
            #
            # Both of these default to True, and both inject substantial tool
            # and prompt scaffolding ahead of every message. Together they took
            # "Tell me a random fun fact about the Roman Empire" from ten words
            # to an `input_tokens` of 2050, and llama3.1:8b read all that
            # scaffolding as its actual instructions: it answered by inventing
            # a `create_tasks` function and asserting it could not generate
            # text at all.
            #
            # That is a small-model failure, not a broken one — the same model
            # writes fine through the raw API, at the same 35.8 tok/s. An 8B is
            # simply captured by a large tool preamble in a way a frontier
            # model is not. Neither feature is useful here: automations schedule
            # recurring prompts, and the code interpreter runs Python in the
            # browser via pyodide.
            ENABLE_AUTOMATIONS = "False";
            ENABLE_CODE_INTERPRETER = "False";

            # Each of these fires an *extra* model call per message, on top of
            # the answer. On a 14B at ~12 tok/s that is a wait you can feel.
            # Titles are worth their call — they are how a conversation is
            # findable later — so that one stays on.
            ENABLE_TAGS_GENERATION = "False";
            ENABLE_FOLLOW_UP_GENERATION = "False";
            ENABLE_TITLE_GENERATION = "True";
          };

          environmentFile = config.sops.templates."open-webui.env".path;
        };

        # One secret, two readers with different owners: kanidm reads the raw
        # value as `basicSecretFile`, while open-webui needs it shaped as an
        # environment assignment. A template renders the second from the first
        # rather than duplicating the secret — the technique services/attic.nix
        # uses for its push token.
        sops.secrets."keys/open-webui/oauth-client-secret".owner = "kanidm";
        sops.templates."open-webui.env" = {
          content = ''
            OAUTH_CLIENT_SECRET=${config.sops.placeholder."keys/open-webui/oauth-client-secret"}
          '';
          owner = "open-webui";
        };

        # The same DynamicUser + StateDirectory trap the engine above hits, and
        # it matters more here: this state is the chats, the accounts and the
        # knowledge bases, so a UID that changes across boots loses real data
        # rather than a re-downloadable model.
        users.users.open-webui = {
          isSystemUser = true;
          group = "open-webui";
          home = config.services.open-webui.stateDir;
        };
        users.groups.open-webui = {};

        systemd.services.open-webui.serviceConfig = {
          DynamicUser = lib.mkForce false;
          User = "open-webui";
          Group = "open-webui";
        };

        cosmos.system.impermanence.persist.directories = [
          {
            directory = config.services.open-webui.stateDir;
            user = "open-webui";
            group = "open-webui";
            mode = "0750";
          }
        ];

        services.kanidm.provision = {
          groups.open-webui-users = {
            overwriteMembers = false;
            members = ["lvdar"];
          };

          systems.oauth2.open-webui = {
            displayName = "Open WebUI";
            basicSecretFile = config.sops.secrets."keys/open-webui/oauth-client-secret".path;
            originUrl = "https://${cfg.domain}/oauth/oidc/callback";
            originLanding = "https://${cfg.domain}";
            scopeMaps.open-webui-users = ["openid" "email" "profile"];

            # kanidm requires PKCE; Open WebUI's authlib client does not send a
            # code challenge for a generic OIDC provider, so the exchange fails
            # at the token endpoint with an opaque invalid_request. Same
            # concession jellyfin.nix and traccar.nix already make, and for the
            # same reason — the alternative is patching the application.
            allowInsecureClientDisablePkce = true;

            # Without this the OIDC `preferred_username` is the full SPN
            # (lvdar@auth.lvdar.nl), which becomes the display name.
            preferShortUsername = true;
          };
        };
      };
    };
  };
}
