# pkgs.python3Packages.tino — the `tino` Python package (github:confirm/tino),
# registered into python3Packages rather than built as a standalone
# application: it has no console-script entry point of its own — upstream
# runs it *as* a gunicorn worker target, "tino:create_app()" — so
# services/tino.nix composes the actual run environment with
# `python3.withPackages`.
#
# Upstream ships and supports only a Docker image, and calls a non-Docker
# install "not recommended and unsupported". That warning is about a manual
# Ubuntu-style install (chasing Python 3.14, the Typst CLI, and git-lfs by
# hand), not about anything Nix-specific: every runtime dependency already
# has a proper nixpkgs derivation, including the two Rust-backed ones
# (pycrdt, pycrdt-websocket), and nixpkgs' own `typst` package happens to
# already be pinned to exactly the 0.15.1 upstream's Dockerfile bundles. So
# packaging it natively costs nothing that "unsupported" actually protects
# against, and keeps it in the same shape as every other service here rather
# than being this fleet's first Docker container.
#
# Two assets upstream's own `make build` vendors in are NOT part of the git
# source and therefore not covered by a plain `buildPythonPackage` over it:
#
#   - tino/static/css/vendor/colours.css, curled from a corporate design URL
#     at build time (`make vendor-css`). Every `--cd-*` and `--accent-*` CSS
#     custom property the whole UI is styled with — including the login
#     button — comes from this file. Without it those variables are simply
#     undefined, which is exactly "the login button is invisible": white
#     text on an unset (transparent) background.
#   - tino/static/js/vendor/codemirror.js, an esbuild bundle of the editor's
#     CodeMirror dependencies (`make vendor-js` / `npm run build`).
#
# Both are fetched/built here and spliced into the source tree before the
# Python package is built, so `tool.setuptools.package-data`'s existing
# `static/**/*` glob picks them up like any other static file.
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

      # package-lock.json is gitignored upstream (never committed), so
      # `fetchNpmDeps` has nothing to lock against in `src` itself. Generated
      # once against this tag's package.json (`npm install
      # --package-lock-only`) and carried here rather than regenerated on
      # every eval — bump it by hand alongside `version`.
      srcWithNpmLock = final.runCommand "tino-src-with-npm-lock" {} ''
        cp -r ${src} $out
        chmod -R u+w $out
        install -Dm444 ${./_tino/package-lock.json} $out/package-lock.json
      '';

      # esbuild's npm package normally downloads a prebuilt binary for its
      # own platform in a postinstall script, which has no network access
      # under the Nix sandbox. ESBUILD_BINARY_PATH is esbuild's own escape
      # hatch for exactly this: point it at nixpkgs' own (Go-built) esbuild
      # instead, and skip npm's install scripts entirely.
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

              # Upstream pins every dependency with `==`; nixpkgs carries
              # newer, compatible releases of all of them, and matching the
              # pin exactly would mean tracking tino's lockstep on every
              # nixpkgs bump for no correctness reason FastAPI/uvicorn/
              # gunicorn don't already give across minor versions.
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

              # gitattributes ships at the repo root (routes bucket git repos
              # through git-lfs — see services/tino.nix), not inside the
              # `tino` package dir, so `tool.setuptools.package-data` never
              # installs it. Carried out as a share/ file instead of
              # duplicating its content in the NixOS module.
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
