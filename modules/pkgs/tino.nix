# tino — the `tino` Python package (github:confirm/tino), registered into
# python3Packages rather than built standalone: no console-script entry
# point (upstream runs it as a gunicorn worker, "tino:create_app()");
# services/tino.nix composes the run env with python3.withPackages. Upstream
# supports only Docker; native packaging is deliberate — this fleet runs no
# containers.
#
# Two assets upstream's `make build` vendors are NOT in the git source, so a
# plain buildPythonPackage misses them: colours.css (every --cd-*/--accent-*
# CSS custom property the UI styles with — without it the login button is
# white on an unset background, i.e. invisible) and codemirror.js (an
# esbuild bundle). Both are fetched/built here and spliced in pre-build so
# package-data's static/**/* glob picks them up.
{...}: {
  nixpkgs.overlays = [
    (final: prev: let
      version = "1.20.1";

      src = final.fetchFromGitHub {
        owner = "confirm";
        repo = "tino";
        tag = version;
        hash = "sha256-EnFlCeX0QGNfuTPKF8kveg1Z7ryAsqQbUoQv1BRZw1I=";
      };

      # https://github.com/confirm/tino/blob/1.20.1/Makefile — vendor-css.
      coloursCss = final.fetchurl {
        url = "https://assets.confirm.ch/colours.css";
        hash = "sha256-QIMWQAGqD1V15fCZ8vUjGL6QE+BiHrFVdkbRnejvQE4=";
      };

      # package-lock.json is gitignored upstream, so fetchNpmDeps has
      # nothing to lock against in src; generated once per tag and carried
      # here — bump it by hand alongside `version`.
      srcWithNpmLock = final.runCommand "tino-src-with-npm-lock" {} ''
        cp -r ${src} $out
        chmod -R u+w $out
        install -Dm444 ${./_tino/package-lock.json} $out/package-lock.json
      '';

      # esbuild's npm postinstall downloads a prebuilt binary — no network
      # in the sandbox. ESBUILD_BINARY_PATH + --ignore-scripts point it at
      # nixpkgs' esbuild instead.
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

              dependencies = with pyFinal; [
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
              ];

              postPatch = ''
                install -Dm444 ${coloursCss} tino/static/css/vendor/colours.css
                install -Dm444 ${codemirrorBundle}/codemirror.js tino/static/js/vendor/codemirror.js

                # GEWIS's own crest (github.com/gewis/aurora's
                # infoscherm/public_html/images/gewislogo.svg), recoloured
                # from white — meant to sit on their brand-red background —
                # to that same red, so it reads on TINO's light login card
                # instead of vanishing into it. Wrapped as a <symbol id="logo">
                # because that's what login.html/index.html's
                # <use xlink:href="/img/logo.svg#logo"/> expects; the source
                # file is just the crest's <g>, not a symbol.
                install -Dm444 ${./_tino/logo.svg} tino/static/img/logo.svg

                # login.html/index.html both wrap that <use> in an <svg
                # viewBox="0 0 407 200"> sized only by CSS height (.logo,
                # .login-logo) — sized for upstream's own wide wordmark
                # logo. GEWIS's crest is close to square (its own symbol
                # viewBox is 580x580), so under the default
                # preserveAspectRatio="xMidYMid meet" it was being scaled
                # to fit the *height* of that wide box and centered with a
                # lot of wasted width either side — visibly tiny at the
                # CSS height it was actually given. Squaring off the
                # wrapper viewBox to match removes the wasted space so the
                # crest fills the full height/width CSS gives it.
                substituteInPlace tino/static/index.html tino/static/login.html \
                  --replace-fail 'viewBox="0 0 407 200"' 'viewBox="0 0 200 200"'

                # .login-logo's 64px height was sized for upstream's own
                # compact wordmark, which reads fine that small; GEWIS's
                # crest carries a full ring of circular text around the
                # emblem that needs real size to stay legible. The login
                # card has the room — its mascot image sits at 250px next
                # to it — so this only affects the one clearly-branded
                # moment, not the toolbar's small icon-height logo (left
                # at 22px; that's app chrome, not a place to grow into).
                substituteInPlace tino/static/login.html \
                  --replace-fail 'height: 64px;' 'height: 110px;'

                # tino stores the whole raw OIDC id_token in its
                # (client-side, single signed-cookie) session purely to pass
                # as id_token_hint on RP-initiated logout — a UX nicety that
                # skips kanidm's own re-confirmation, nothing auth-relevant
                # depends on it. kanidm bakes the identity's full group
                # membership into every id_token it issues once the "groups"
                # scope is granted (unavoidable — see services/kanidm.nix —
                # independent of claimMaps), and for a broad admin identity
                # that JWT alone is 4KB+, over the ~4KB browsers cap a single
                # cookie at: login completed server-side every time but the
                # session cookie was silently dropped client-side. Never
                # storing it removes the ceiling entirely rather than
                # picking a size threshold that just moves where this breaks
                # again as group counts grow.
                substituteInPlace tino/auth.py \
                  --replace-fail \
                    "    if token.get('id_token'):" \
                    "    if False:  # id_token intentionally never kept in the session"
              '';

              # gitattributes sits at the repo root (git-lfs routing —
              # services/tino.nix), so package-data never installs it;
              # carried as a share/ file instead.
              postInstall = ''
                install -Dm444 tino/gitattributes $out/share/tino/gitattributes
              '';

              # setuptools_scm derives the version from git metadata, which
              # fetchFromGitHub does not provide.
              SETUPTOOLS_SCM_PRETEND_VERSION = version;

              pythonImportsCheck = ["tino"];

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
