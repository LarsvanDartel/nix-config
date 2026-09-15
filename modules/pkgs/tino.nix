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
