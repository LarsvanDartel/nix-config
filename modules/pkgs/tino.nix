# tino — the `tino` Python package (github:confirm/tino) in python3Packages, with the untracked colours.css and codemirror.js spliced in.
{...}: {
  nixpkgs.overlays = [
    (final: prev: let
      version = "1.22.0";

      src = final.fetchFromGitHub {
        owner = "confirm";
        repo = "tino";
        tag = version;
        hash = "sha256-OS7XZdqGu98Y9hNO7JihBV1sU3ATx91xZAYNW8bGiPc=";
      };

      # https://github.com/confirm/tino/blob/1.22.0/Makefile — vendor-css.
      coloursCss = final.fetchurl {
        url = "https://assets.confirm.ch/colours.css";
        hash = "sha256-QIMWQAGqD1V15fCZ8vUjGL6QE+BiHrFVdkbRnejvQE4=";
      };

      # package-lock.json is gitignored upstream; carried here — bump by hand
      # alongside `version`.
      srcWithNpmLock = final.runCommand "tino-src-with-npm-lock" {} ''
        cp -r ${src} $out
        chmod -R u+w $out
        install -Dm444 ${./_tino/package-lock.json} $out/package-lock.json
      '';

      # esbuild's postinstall downloads a binary (no network in the sandbox);
      # point it at nixpkgs' esbuild instead.
      codemirrorBundle = final.buildNpmPackage {
        pname = "tino-codemirror-bundle";
        inherit version;
        src = srcWithNpmLock;
        npmDepsHash = "sha256-m/Hewi8AMEVFdGLkt1yKiFGP2Xhjlkh3FtulvNMYBIs=";
        npmFlags = ["--ignore-scripts"];
        env.ESBUILD_BINARY_PATH = "${final.esbuild}/bin/esbuild";
        installPhase = ''
          runHook preInstall
          mkdir -p $out
          cp tino/static/js/vendor/codemirror.js $out/codemirror.js
          runHook postInstall
        '';
      };

      pythonPackagesExtensions =
        prev.pythonPackagesExtensions
        ++ [
          (pyFinal: _pyPrev: {
            tino = pyFinal.buildPythonPackage rec {
              pname = "tino";
              inherit version src;
              pyproject = true;

              build-system = with pyFinal; [setuptools setuptools-scm wheel];

              # Upstream pins every dependency with `==`; relaxed rather
              # than tracking tino's lockstep on every nixpkgs bump.
              pythonRelaxDeps = true;

              # uvicorn[standard] upstream: without its websockets extra the
              # collab WebSocket is refused ("Unsupported upgrade request").
              dependencies = with pyFinal;
                [
                  anyio
                  authlib
                  fastapi
                  mcp
                  gitpython
                  gunicorn
                  httpx
                  itsdangerous
                  pycrdt
                  pycrdt-websocket
                  python-multipart
                  pyyaml
                  uvicorn
                ]
                ++ uvicorn.optional-dependencies.standard;

              postPatch = ''
                install -Dm444 ${coloursCss} tino/static/css/vendor/colours.css
                install -Dm444 ${codemirrorBundle}/codemirror.js tino/static/js/vendor/codemirror.js

                # Same lockstep pinning as pythonRelaxDeps, but on the build
                # backend, which that does not reach.
                substituteInPlace pyproject.toml \
                  --replace-fail "'setuptools>=84.2.1'" "'setuptools'"

                # GEWIS's crest (gewis/aurora gewislogo.svg), recoloured to its brand red for the light login
                # card and wrapped as <symbol id="logo"> for the templates' <use xlink:href="/img/logo.svg#logo"/>.
                install -Dm444 ${./_tino/logo.svg} tino/static/img/logo.svg

                # Square the templates' 407x200 wrapper viewBox: the near-square crest otherwise renders tiny.
                substituteInPlace tino/static/index.html tino/static/login.html \
                  --replace-fail 'viewBox="0 0 407 200"' 'viewBox="0 0 200 200"'

                # The crest's ring of text needs more than upstream's 64px login logo; the toolbar logo stays.
                substituteInPlace tino/static/login.html \
                  --replace-fail 'height: 64px;' 'height: 110px;'

                # Never keep the id_token in the cookie session: with the groups scope it exceeds the ~4KB
                # browser cap and the cookie is silently dropped. It only fed id_token_hint on logout.
                substituteInPlace tino/auth.py \
                  --replace-fail \
                    "    if token.get('id_token'):" \
                    "    if False:  # id_token intentionally never kept in the session"

                # Nix files are text, not LFS, or TINO's UI shows them perpetually modified. Fixed here because
                # a bucket-local .gitattributes is hidden from TINO's listing and git-remote-tino clones.
                cat >> tino/gitattributes <<'EOF'
                *.nix text !filter !diff !merge text
                *.lock text !filter !diff !merge text
                EOF
              '';

              # gitattributes sits at the repo root, so package-data never
              # installs it.
              postInstall = ''
                install -Dm444 tino/gitattributes $out/share/tino/gitattributes
              '';

              # setuptools_scm needs git metadata fetchFromGitHub lacks. Under `env`: with structured attrs
              # a top-level attribute is a shell variable, not exported.
              env.SETUPTOOLS_SCM_PRETEND_VERSION = version;

              pythonImportsCheck = ["tino"];

              # Deps are relaxed, so upstream's suite proves a nixpkgs bump left them API-compatible.
              nativeCheckInputs = [pyFinal.pytestCheckHook final.gitMinimal final.typst];
              # Asserts the id_token_hint the auth.py patch above removes.
              disabledTests = ["test_logout_includes_id_token_hint"];

              meta = {
                description = "Collaborative, self-hosted editing platform around Typst";
                homepage = "https://github.com/confirm/tino";
                license = final.lib.licenses.agpl3Only;
              };
            };
          })
        ];
    in {
      inherit pythonPackagesExtensions;
    })
  ];
}
